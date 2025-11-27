import express from "express";
import dotenv from "dotenv";
import { z } from "zod";
import axios from "axios";
import { config } from "./config.js";

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

app.post("/settlements", (req, res) => {
  if (config.computeWebhookKey && req.headers["x-api-key"] !== config.computeWebhookKey) {
    return res.status(401).json({ error: "invalid api key" });
  }

  console.log("Settlement received from EigenCompute", req.body);
  // TODO: verify attestation, relay to off-chain signing service or direct on-chain submission
  res.status(204).send();
});

app.listen(config.port, () => {
  console.log(`EigenDark Gateway listening on :${config.port}`);
});

