import { config } from "./config.js";
import { isSubmitterReady, submitToHook } from "./hookSubmitter.js";
import {
  listPendingSettlements,
  markFailed,
  markSubmitted,
} from "./settlementStore.js";
import { logger } from "./logger.js";
import { recordHookSubmission, recordRetryAttempt, setPendingSettlements } from "./metrics.js";

let intervalHandle: NodeJS.Timeout | undefined;
let running = false;

export function startRetryWorker() {
  if (intervalHandle || config.retryIntervalMs <= 0) {
    return;
  }

  intervalHandle = setInterval(runRetryCycle, config.retryIntervalMs);
  logger.info({ intervalMs: config.retryIntervalMs }, "Starting settlement retry worker");
  runRetryCycle().catch((error) => {
    logger.error({ err: error instanceof Error ? error.message : String(error) }, "retry worker failed");
  });
}

export async function runRetryCycle() {
  if (running || !isSubmitterReady()) {
    return {
      attempted: 0,
      submitted: 0,
      failed: 0,
      skipped: running ? "worker_busy" : "submitter_unavailable",
    };
  }

  running = true;
  const now = Date.now();
  const summary = {
    attempted: 0,
    submitted: 0,
    failed: 0,
  };

  try {
    const pending = listPendingSettlements();
    for (const entry of pending) {
      if (entry.lastAttemptAt && now - entry.lastAttemptAt < config.retryIntervalMs) {
        continue;
      }

      summary.attempted += 1;
      const start = Date.now();
      try {
        const txHash = await submitToHook(entry.payload, entry.verified);
        recordHookSubmission("success", Date.now() - start);
        if (txHash) {
          markSubmitted(entry.clientOrderId, txHash);
          summary.submitted += 1;
          logger.info({ orderId: entry.clientOrderId, txHash }, "Retried settlement submission");
        }
      } catch (error) {
        const message = (error as Error).message || "hook submission failed";
        recordHookSubmission("error");
        markFailed(entry.clientOrderId, message);
        summary.failed += 1;
        logger.warn({ orderId: entry.clientOrderId, err: message }, "Settlement retry failed");
      }
    }
  } finally {
    running = false;
    recordRetryAttempt(summary.failed > 0 ? "error" : "success");
    setPendingSettlements(listPendingSettlements().length);
  }

  return summary;
}

