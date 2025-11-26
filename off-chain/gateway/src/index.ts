import express from "express";
import dotenv from "dotenv";
import { z } from "zod";
import axios from "axios";

dotenv.config();

const app = express();
app.use(express.json());

const computeClient = axios.create({
  baseURL: process.env.EIGEN_COMPUTE_URL ?? "http://127.0.0.1:8080",
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
  const apiKey = process.env.COMPUTE_WEBHOOK_KEY;
  if (apiKey && req.headers["x-api-key"] !== apiKey) {
    return res.status(401).json({ error: "invalid api key" });
  }

  console.log("Settlement received from EigenCompute", req.body);
  // TODO: verify attestation, relay to off-chain signing service or direct on-chain submission
  res.status(204).send();
});

const port = Number(process.env.PORT ?? 4000);
app.listen(port, () => {
  console.log(`EigenDark Gateway listening on :${port}`);
});

