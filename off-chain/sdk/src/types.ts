export type OrderRequest = {
  trader: string;
  tokenIn: string;
  tokenOut: string;
  amount: string;
  limitPrice: string;
  payload: string;
};

export type SettlementRecord = {
  clientOrderId: string;
  payload: unknown;
  verified: unknown;
  status: "verified" | "submitted" | "failed";
  lastAttemptAt?: number;
  txHash?: string;
  error?: string;
};

export type HealthStatus = {
  status: string;
  timestamp?: number;
  [key: string]: unknown;
};

export type RetrySummary = {
  attempted: number;
  submitted: number;
  failed: number;
  skipped?: string;
};

export type EigenDarkClientConfig = {
  gatewayUrl: string;
  computeUrl?: string;
  clientApiKey?: string;
  adminApiKey?: string;
  timeoutMs?: number;
};

