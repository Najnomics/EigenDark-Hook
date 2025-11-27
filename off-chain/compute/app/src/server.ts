import express from "express";
import { z } from "zod";
import axios from "axios";
import { keccak256, stringToHex, parseUnits } from "viem";
import { config } from "./config.js";
import { SettlementQueue } from "./settlementQueue.js";
import { signSettlement } from "./attestation.js";
import { EncryptedOrder, QueueItem, SettlementInstruction } from "./types.js";

const app = express();
const queue = new SettlementQueue();

app.use(express.json());

const orderSchema = z.object({
  trader: z.string().min(1),
  tokenIn: z.string().min(1),
  tokenOut: z.string().min(1),
  amount: z.string().min(1),
  limitPrice: z.string().min(1),
  payload: z.string().min(1),
});

app.get("/health", (_req, res) => {
  res.json({
    status: "ok",
    measurement: config.measurement,
    hook: config.hookAddress,
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

app.post("/orders", async (req, res) => {
  const parsed = orderSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: parsed.error.flatten() });
  }

  const entry = queue.enqueue(parsed.data);
  processOrder(entry.order).catch((err) => {
    console.error("order processing failed", err);
    queue.markFailed(entry.order.orderId, (err as Error).message);
  });

  res.status(202).json({ orderId: entry.order.orderId, status: entry.status });
});

queue.onChange((item) => {
  if (item.status === "settled" && item.settlement) {
    notifyGateway(item).catch((err) => {
      console.error("failed to notify gateway", err);
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
      timeout: 5_000,
    }
  );
}

const port = config.port;
app.listen(port, "0.0.0.0", () => {
  console.log(
    `EigenDark EigenCompute app listening on :${port} (measurement ${config.measurement})`
  );
});

