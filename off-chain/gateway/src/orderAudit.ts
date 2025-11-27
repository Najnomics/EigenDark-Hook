import { promises as fs } from "fs";
import path from "path";
import { config } from "./config.js";
import { logger } from "./logger.js";

const ordersLogPath = path.join(config.storageDir, "orders.log");
let storageReady = false;

export async function logOrderSubmission(orderId: string, payload: unknown) {
  await ensureStorage();
  const entry = {
    orderId,
    receivedAt: Date.now(),
    payload,
  };

  try {
    await fs.appendFile(ordersLogPath, `${JSON.stringify(entry)}\n`, "utf8");
  } catch (error) {
    logger.warn(
      { orderId, err: error instanceof Error ? error.message : String(error) },
      "Failed to append order audit log",
    );
  }
}

async function ensureStorage() {
  if (storageReady) return;
  await fs.mkdir(config.storageDir, { recursive: true });
  storageReady = true;
}

