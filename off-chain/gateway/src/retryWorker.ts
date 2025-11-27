import { config } from "./config.js";
import { isSubmitterReady, submitToHook } from "./hookSubmitter.js";
import {
  listPendingSettlements,
  markFailed,
  markSubmitted,
} from "./settlementStore.js";
import { logger } from "./logger.js";

let intervalHandle: NodeJS.Timeout | undefined;
let running = false;

export function startRetryWorker() {
  if (intervalHandle || config.retryIntervalMs <= 0) {
    return;
  }

  const run = async () => {
    if (running || !isSubmitterReady()) {
      return;
    }

    running = true;
    const now = Date.now();
    try {
      const pending = listPendingSettlements();
      for (const entry of pending) {
        if (entry.lastAttemptAt && now - entry.lastAttemptAt < config.retryIntervalMs) {
          continue;
        }

        try {
          const txHash = await submitToHook(entry.payload, entry.verified);
          if (txHash) {
            markSubmitted(entry.clientOrderId, txHash);
            logger.info({ orderId: entry.clientOrderId, txHash }, "Retried settlement submission");
          }
        } catch (error) {
          const message = (error as Error).message || "hook submission failed";
          markFailed(entry.clientOrderId, message);
          logger.warn({ orderId: entry.clientOrderId, err: message }, "Settlement retry failed");
        }
      }
    } finally {
      running = false;
    }
  };

  intervalHandle = setInterval(run, config.retryIntervalMs);
  logger.info({ intervalMs: config.retryIntervalMs }, "Starting settlement retry worker");
  run().catch((error) => {
    logger.error({ err: error instanceof Error ? error.message : String(error) }, "retry worker failed");
  });
}

