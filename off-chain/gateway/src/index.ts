import express from "express";
import dotenv from "dotenv";
import { z } from "zod";

dotenv.config();

const app = express();
app.use(express.json());

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

app.post("/orders", (req, res) => {
  const parsed = orderSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: parsed.error.flatten() });
  }

  // Placeholder: persist order, forward to EigenCompute queue, etc.
  const orderId = crypto.randomUUID();
  console.log("Received order", { orderId, order: parsed.data });

  res.status(202).json({ orderId, status: "queued" });
});

const port = Number(process.env.PORT ?? 4000);
app.listen(port, () => {
  console.log(`EigenDark Gateway listening on :${port}`);
});

