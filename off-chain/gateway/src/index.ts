import express from "express";
import { z } from "zod";
import axios from "axios";
import { config } from "./config.js";
import { verifySettlement } from "./settlementVerifier.js";
import { submitToHook } from "./hookSubmitter.js";
import { SettlementPayload } from "./types.js";
import {
  getSettlement,
  initSettlementStore,
  markFailed,
  markSubmitted,
  serializeSettlement,
  upsertSettlement,
} from "./settlementStore.js";
import { startRetryWorker } from "./retryWorker.js";

const app = express();
app.use(express.json());

const computeClient = axios.create({
  baseURL: config.computeUrl,
  timeout: 5000,
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

app.post("/orders", async (req, res) => {
  const parsed = orderSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: parsed.error.flatten() });
  }

  try {
    const response = await computeClient.post("/orders", parsed.data);
    res.status(response.status).json(response.data);
  } catch (error) {
    console.error("Unable to forward order to EigenCompute", error);
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
    console.log("Verified settlement", serializeSettlement(record));

    try {
      const txHash = await submitToHook(payload, verified);
      if (txHash) {
        markSubmitted(record.clientOrderId, txHash);
      }
    } catch (error) {
      const message = (error as Error).message || "hook submission failed";
      console.error("Failed to submit settlement", message);
      markFailed(record.clientOrderId, message);
      return res.status(502).json({ error: "hook_submission_failed" });
    }

    res.status(204).send();
  } catch (error) {
    console.error("Invalid settlement attestation", error);
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

async function bootstrap() {
  await initSettlementStore();
  startRetryWorker();
  app.listen(config.port, () => {
    console.log(`EigenDark Gateway listening on :${config.port}`);
  });
}

bootstrap().catch((error) => {
  console.error("Failed to start gateway", error);
  process.exit(1);
});

