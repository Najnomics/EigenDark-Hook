import express from "express";
import dotenv from "dotenv";
import { z } from "zod";
import axios from "axios";
import { config } from "./config.js";
import { verifySettlement } from "./settlementVerifier.js";
import { submitToHook } from "./hookSubmitter.js";
import { SettlementPayload, VerifiedSettlement } from "./types.js";

dotenv.config();

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
    orderId: z.string().min(1),
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

const verifiedSettlements = new Map<string, VerifiedSettlement>();

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

  try {
    const payload = parsed.data as SettlementPayload;
    const verified = await verifySettlement(payload);
    verifiedSettlements.set(verified.clientOrderId, verified);
    console.log("Verified settlement", verified);
    await submitToHook(payload, verified);
    res.status(204).send();
  } catch (error) {
    console.error("Invalid settlement attestation", error);
    res.status(400).json({ error: "invalid_attestation" });
  }
});

app.get("/settlements/:orderId", (req, res) => {
  const item = verifiedSettlements.get(req.params.orderId);
  if (!item) {
    return res.status(404).json({ error: "settlement not found" });
  }
  res.json(item);
});

app.listen(config.port, () => {
  console.log(`EigenDark Gateway listening on :${config.port}`);
});

