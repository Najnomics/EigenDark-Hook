import { Counter, Gauge, Histogram, Registry, collectDefaultMetrics } from "prom-client";

const registry = new Registry();
collectDefaultMetrics({ register: registry });

const httpRequests = new Counter({
  name: "gateway_http_requests_total",
  help: "Total HTTP requests handled by the EigenDark gateway",
  labelNames: ["method", "route", "status"] as const,
  registers: [registry],
});

const orderForwardCounter = new Counter({
  name: "gateway_order_requests_total",
  help: "Orders forwarded to EigenCompute by result",
  labelNames: ["result"] as const,
  registers: [registry],
});

const settlementCounter = new Counter({
  name: "gateway_settlement_webhooks_total",
  help: "Settlement webhooks processed from EigenCompute",
  labelNames: ["result"] as const,
  registers: [registry],
});

const hookSubmissionCounter = new Counter({
  name: "gateway_hook_submissions_total",
  help: "On-chain settlement submissions attempted by the gateway",
  labelNames: ["result"] as const,
  registers: [registry],
});

const retryCounter = new Counter({
  name: "gateway_retry_worker_total",
  help: "Retry cycles executed by the gateway",
  labelNames: ["result"] as const,
  registers: [registry],
});

const hookLatency = new Histogram({
  name: "gateway_hook_submission_latency_ms",
  help: "Latency for submitting settlements to the hook",
  buckets: [50, 100, 250, 500, 1000, 2000, 5000],
  registers: [registry],
});

const pendingSettlementsGauge = new Gauge({
  name: "gateway_pending_settlements",
  help: "Current number of settlements awaiting submission",
  registers: [registry],
});

export function recordHttpRequest(method: string, route: string, status: number) {
  httpRequests.inc({ method, route, status: status.toString() });
}

export function recordOrderForward(result: "success" | "error") {
  orderForwardCounter.inc({ result });
}

export function recordSettlementWebhook(result: "accepted" | "rejected") {
  settlementCounter.inc({ result });
}

export function recordHookSubmission(result: "success" | "error", latencyMs?: number) {
  hookSubmissionCounter.inc({ result });
  if (typeof latencyMs === "number") {
    hookLatency.observe(latencyMs);
  }
}

export function recordRetryAttempt(result: "success" | "error") {
  retryCounter.inc({ result });
}

export function setPendingSettlements(count: number) {
  pendingSettlementsGauge.set(count);
}

export async function getMetricsSnapshot(): Promise<string> {
  return registry.metrics();
}


