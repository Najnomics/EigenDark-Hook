import { config } from "./config.js";
import { isSubmitterReady, submitToHook } from "./hookSubmitter.js";
import {
  listPendingSettlements,
  markFailed,
  markSubmitted,
} from "./settlementStore.js";

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
          }
        } catch (error) {
          const message = (error as Error).message || "hook submission failed";
          markFailed(entry.clientOrderId, message);
        }
      }
    } finally {
      running = false;
    }
  };

  intervalHandle = setInterval(run, config.retryIntervalMs);
  run().catch((error) => console.error("retry worker failed", error));
}

