import express from "express";
import { z } from "zod";
import axios from "axios";
import { keccak256, stringToHex, parseUnits } from "viem";
import { config } from "./config.js";
import { SettlementQueue } from "./settlementQueue.js";
import { signSettlement } from "./attestation.js";
import { EncryptedOrder, QueueItem, SettlementInstruction } from "./types.js";
import { logger } from "./logger.js";
import { attachRequestId } from "./requestContext.js";
import { requireGatewayAuth } from "./auth.js";

const app = express();
const queue = new SettlementQueue(config.maxPendingOrders);

app.use(express.json({ limit: "1mb" }));
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
  });
  next();
});

const address = z.string().regex(/^0x[0-9a-fA-F]{40}$/, "invalid address");
const decimalString = z
  .string()
  .regex(/^\d+(\.\d+)?$/, "must be a positive decimal string")
  .refine((val) => Number(val) > 0, "value must be positive");

const orderSchema = z
  .object({
    trader: address,
    tokenIn: address,
    tokenOut: address,
    amount: decimalString,
    limitPrice: decimalString,
    payload: z.string().min(1),
  })
  .refine((order) => order.tokenIn.toLowerCase() !== order.tokenOut.toLowerCase(), {
    message: "tokenIn and tokenOut must differ",
    path: ["tokenOut"],
  });

app.get("/health", (_req, res) => {
  res.json({
    status: "ok",
    measurement: config.measurement,
    hook: config.hookAddress,
    pendingOrders: queue.size(),
    timestamp: Date.now(),
  });
});

app.get("/orders/:orderId", (req, res) => {
  const order = queue.get(req.params.orderId);
  if (!order) {
    return res.status(404).json({ error: "order not found" });
  }
  res.json(order);
});

app.get("/metrics", (_req, res) => {
  const stats = queue.stats();
  res.json({
    pending: queue.size(),
    stats,
  });
});

app.post("/orders", requireGatewayAuth, async (req, res) => {
  const parsed = orderSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: parsed.error.flatten() });
  }

  if (queue.size() >= config.maxPendingOrders) {
    logger.warn({ reqId: req.requestId }, "order queue at capacity");
    return res.status(503).json({ error: "order_queue_full" });
  }

  const entry = queue.enqueue(parsed.data);
  processOrder(entry.order).catch((err) => {
    const message = (err as Error).message;
    logger.error({ orderId: entry.order.orderId, err: message }, "order processing failed");
    queue.markFailed(entry.order.orderId, message);
  });

  res.status(202).json({ orderId: entry.order.orderId, status: entry.status });
});

queue.onChange((item) => {
  logger.info({ orderId: item.order.orderId, status: item.status }, "queue status update");
  if (item.status === "settled" && item.settlement) {
    notifyGateway(item).catch((err) => {
      logger.error({ orderId: item.order.orderId, err: (err as Error).message }, "failed to notify gateway");
    });
  }
});

async function processOrder(order: EncryptedOrder) {
  queue.markProcessing(order.orderId);

  // Placeholder for enclave execution (decrypt payload, fetch price, run risk checks)
  await new Promise((resolve) => setTimeout(resolve, 250));

  const settlement = buildSettlement(order);
  const attestation = await signSettlement(settlement);
  queue.markSettled(order.orderId, { settlement, attestation });
}

function buildSettlement(order: EncryptedOrder): SettlementInstruction {
  const poolId = keccak256(
    stringToHex(`${order.tokenIn.toLowerCase()}-${order.tokenOut.toLowerCase()}`)
  ) as `0x${string}`;
  const orderHash = keccak256(stringToHex(order.orderId)) as `0x${string}`;

  const amountIn = parseUnits(order.amount, 18);
  const price = parseUnits(order.limitPrice, 18);
  const delta0 = toInt128(-amountIn);
  const delta1 = toInt128((amountIn * price) / 10n ** 18n);

  return {
    orderId: orderHash,
    poolId,
    trader: order.trader,
    delta0,
    delta1,
    submittedAt: Math.floor(Date.now() / 1000),
    enclaveMeasurement: config.measurement,
  };
}

function toInt128(value: bigint): bigint {
  const min = -(2n ** 127n);
  const max = 2n ** 127n - 1n;
  if (value < min || value > max) {
    throw new Error("Value exceeds int128 range");
  }
  return value;
}

async function notifyGateway(item: QueueItem) {
  if (!item.settlement) return;
  await axios.post(
    config.gatewayWebhookUrl,
    {
      orderId: item.order.orderId,
      settlement: item.settlement.settlement,
      attestation: item.settlement.attestation,
    },
    {
      headers: config.gatewayApiKey ? { "x-api-key": config.gatewayApiKey } : undefined,
      timeout: config.gatewayTimeoutMs,
    },
  );
  logger.info({ orderId: item.order.orderId }, "pushed settlement to gateway");
}

const port = config.port;
app.listen(port, "0.0.0.0", () => {
  logger.info({ port: config.port, measurement: config.measurement }, "EigenDark EigenCompute app listening");
});

