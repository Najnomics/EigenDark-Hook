import express from "express";
import { z } from "zod";
import axios from "axios";
import { config } from "./config.js";
import { verifySettlement } from "./settlementVerifier.js";
import { submitToHook, isSubmitterReady } from "./hookSubmitter.js";
import { SettlementPayload } from "./types.js";
import {
  getSettlement,
  initSettlementStore,
  markFailed,
  markSubmitted,
  serializeSettlement,
  upsertSettlement,
  listPendingSettlements,
} from "./settlementStore.js";
import { startRetryWorker, runRetryCycle } from "./retryWorker.js";
import { requireClientAuth, requireAdminAuth } from "./auth.js";
import { logOrderSubmission } from "./orderAudit.js";
import { attachRequestId } from "./requestContext.js";
import { logger } from "./logger.js";
import { orderRateLimiter, adminRateLimiter } from "./rateLimit.js";
import {
  getMetricsSnapshot,
  recordHttpRequest,
  recordHookSubmission,
  recordOrderForward,
  recordSettlementWebhook,
  setPendingSettlements,
} from "./metrics.js";

const app = express();
app.use(express.json());
app.use(attachRequestId);
app.use((req, res, next) => {
  const start = Date.now();
  res.on("finish", () => {
    logger.info(
      {
        reqId: req.requestId,
        method: req.method,
        path: req.path,
        status: res.statusCode,
        durationMs: Date.now() - start,
      },
      "request completed",
    );
    recordHttpRequest(req.method, req.path, res.statusCode);
  });
  next();
});

const computeClient = axios.create({
  baseURL: config.computeUrl,
  timeout: 5000,
  headers: config.computeWebhookKey ? { "x-api-key": config.computeWebhookKey } : undefined,
});

const orderSchema = z.object({
  trader: z.string().min(1),
  tokenIn: z.string().min(1),
  tokenOut: z.string().min(1),
  amount: z.string().min(1),
  limitPrice: z.string().min(1),
  payload: z.string().min(1) // encrypted blob for EigenCompute enclave
});

const settlementSchema = z.object({
  orderId: z.string().min(1),
  settlement: z.object({
    orderId: z.string().regex(/^0x[0-9a-fA-F]{64}$/),
    poolId: z.string().regex(/^0x[0-9a-fA-F]{64}$/),
    trader: z.string().regex(/^0x[0-9a-fA-F]{40}$/),
    delta0: z.string(),
    delta1: z.string(),
    submittedAt: z.number(),
    enclaveMeasurement: z.string().regex(/^0x[0-9a-fA-F]{64}$/),
    metadataHash: z.string().regex(/^0x[0-9a-fA-F]{64}$/),
    sqrtPriceX96: z.string().regex(/^\d+$/, "sqrtPriceX96 must be a base-10 string"),
    twapDeviationBps: z.number().int().nonnegative(),
    checkedLiquidity: z.string().regex(/^\d+$/, "checkedLiquidity must be a base-10 string"),
  }),
  attestation: z.object({
    signature: z.string(),
    digest: z.string(),
    measurement: z.string(),
  }),
});

app.get("/health", (_req, res) => {
  res.json({ status: "ok", timestamp: Date.now() });
});

app.post("/orders", requireClientAuth, orderRateLimiter, async (req, res) => {
  const parsed = orderSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: parsed.error.flatten() });
  }

  try {
    const response = await computeClient.post("/orders", parsed.data);
    if (response.data?.orderId) {
      await logOrderSubmission(response.data.orderId, parsed.data);
    }
    recordOrderForward("success");
    res.status(response.status).json(response.data);
  } catch (error) {
    logger.error(
      { reqId: req.requestId, err: error instanceof Error ? error.message : String(error) },
      "Unable to forward order to EigenCompute",
    );
    recordOrderForward("error");
    res.status(502).json({ error: "failed_to_reach_compute" });
  }
});

app.post("/settlements", async (req, res) => {
  if (config.computeWebhookKey && req.headers["x-api-key"] !== config.computeWebhookKey) {
    return res.status(401).json({ error: "invalid api key" });
  }

  const parsed = settlementSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: parsed.error.flatten() });
  }

  const payload = parsed.data as SettlementPayload;

  try {
    const verified = await verifySettlement(payload);
    const record = upsertSettlement(payload, verified);
    setPendingSettlements(listPendingSettlements().length);
    logger.info({ reqId: req.requestId, settlement: serializeSettlement(record) }, "Verified settlement");
    recordSettlementWebhook("accepted");

    try {
      const hookStart = Date.now();
      const txHash = await submitToHook(payload, verified);
      if (txHash) {
        markSubmitted(record.clientOrderId, txHash);
        recordHookSubmission("success", Date.now() - hookStart);
        setPendingSettlements(listPendingSettlements().length);
      }
    } catch (error) {
      const message = (error as Error).message || "hook submission failed";
      logger.error({ reqId: req.requestId, orderId: record.clientOrderId, err: message }, "Hook submission failed");
      markFailed(record.clientOrderId, message);
      recordHookSubmission("error");
      setPendingSettlements(listPendingSettlements().length);
      return res.status(502).json({ error: "hook_submission_failed" });
    }

    res.status(204).send();
  } catch (error) {
    logger.warn(
      { reqId: req.requestId, err: error instanceof Error ? error.message : String(error) },
      "Invalid settlement attestation",
    );
    recordSettlementWebhook("rejected");
    res.status(400).json({ error: "invalid_attestation" });
  }
});

app.get("/settlements/:orderId", (req, res) => {
  const item = getSettlement(req.params.orderId);
  if (!item) {
    return res.status(404).json({ error: "settlement not found" });
  }
  res.json(serializeSettlement(item));
});

app.get("/admin/stats", requireAdminAuth, adminRateLimiter, (_req, res) => {
  res.json({
    uptimeSeconds: process.uptime(),
    retryIntervalMs: config.retryIntervalMs,
    submitterReady: isSubmitterReady(),
    pendingSettlements: listPendingSettlements().length,
    port: config.port,
  });
});

app.get("/admin/settlements/pending", requireAdminAuth, adminRateLimiter, (req, res) => {
  const limit = Number(req.query.limit ?? 50);
  const pending = listPendingSettlements()
    .slice(0, Number.isFinite(limit) && limit > 0 ? limit : 50)
    .map(serializeSettlement);
  res.json({ count: pending.length, settlements: pending });
});

app.post("/admin/retry", requireAdminAuth, adminRateLimiter, async (_req, res) => {
  const summary = await runRetryCycle();
  setPendingSettlements(listPendingSettlements().length);
  res.json(summary);
});

app.get("/metrics", requireAdminAuth, adminRateLimiter, async (_req, res) => {
  res.set("Content-Type", "text/plain; version=0.0.4");
  res.send(await getMetricsSnapshot());
});

async function bootstrap() {
  await initSettlementStore();
  setPendingSettlements(listPendingSettlements().length);
  startRetryWorker();
  app.listen(config.port, () => {
    logger.info({ port: config.port }, "EigenDark Gateway listening");
  });
}

bootstrap().catch((error) => {
  logger.error({ err: error instanceof Error ? error.message : String(error) }, "Failed to start gateway");
  process.exit(1);
});

