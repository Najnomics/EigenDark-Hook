import "dotenv/config";
import path from "path";

function requireEnv(key: string): string {
  const value = process.env[key];
  if (!value) {
    throw new Error(`Missing required env var: ${key}`);
  }
  return value;
}

export const config = {
  port: Number(process.env.PORT ?? 4000),
  computeUrl: process.env.EIGEN_COMPUTE_URL ?? "http://127.0.0.1:8080",
  computeWebhookKey: process.env.COMPUTE_WEBHOOK_KEY ?? "",
  clientApiKey: process.env.CLIENT_API_KEY ?? "",
  adminApiKey: process.env.ADMIN_API_KEY ?? "",
  chainId: Number(process.env.CHAIN_ID ?? 11155111),
  hookAddress: requireEnv("HOOK_ADDRESS") as `0x${string}`,
  measurement: requireEnv("ATTESTATION_MEASUREMENT") as `0x${string}`,
  rpcUrl: process.env.RPC_URL || process.env.HOOK_RPC_URL,
  submitterKey: process.env.SUBMITTER_KEY || process.env.HOOK_SUBMITTER_KEY,
  storageDir: process.env.GATEWAY_DATA_DIR ?? path.resolve(process.cwd(), "data"),
  retryIntervalMs: Number(process.env.SETTLEMENT_RETRY_MS ?? 30_000),
  orderRateWindowMs: Number(process.env.ORDER_RATE_WINDOW_MS ?? 60_000),
  orderRateMax: Number(process.env.ORDER_RATE_MAX ?? 120),
  adminRateWindowMs: Number(process.env.ADMIN_RATE_WINDOW_MS ?? 60_000),
  adminRateMax: Number(process.env.ADMIN_RATE_MAX ?? 60),
};

