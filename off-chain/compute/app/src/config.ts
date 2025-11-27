import "dotenv/config";
import { z } from "zod";

const address = () => z.string().regex(/^0x[0-9a-fA-F]{40}$/, "invalid address");
const bytes32 = () => z.string().regex(/^0x[0-9a-fA-F]{64}$/, "invalid bytes32");
const privateKey = () => z.string().regex(/^0x[0-9a-fA-F]{64}$/, "invalid private key");

const envSchema = z.object({
  PORT: z.coerce.number().int().default(8080),
  CHAIN_ID: z.coerce.number().int(),
  HOOK_ADDRESS: address(),
  VAULT_ADDRESS: address(),
  ATTESTATION_MEASUREMENT: bytes32(),
  ATTESTOR_PRIVATE_KEY: privateKey(),
  GATEWAY_WEBHOOK_URL: z.string().url(),
  GATEWAY_API_KEY: z.string().optional(),
  ORDER_API_KEY: z.string().optional(),
  MAX_PENDING_ORDERS: z.coerce.number().int().positive().default(500),
  GATEWAY_TIMEOUT_MS: z.coerce.number().int().positive().default(5_000),
  LOG_LEVEL: z.string().optional(),
  PYTH_ENDPOINT: z.string().url().optional(),
  PYTH_TWAP_WINDOW: z.coerce.number().int().positive().max(600).optional(),
  PYTH_PRICE_IDS: z.string().optional(),
});

function parsePriceIdMap(raw?: string): Record<string, string> {
  if (!raw) return {};
  try {
    const parsed = JSON.parse(raw) as Record<string, string>;
    const normalized: Record<string, string> = {};
    for (const [key, value] of Object.entries(parsed)) {
      normalized[key.toLowerCase()] = value;
    }
    return normalized;
  } catch (error) {
    console.warn("Failed to parse PYTH_PRICE_IDS:", (error as Error).message);
    return {};
  }
}

const parsed = envSchema.parse(process.env);

export const config = {
  port: parsed.PORT,
  chainId: parsed.CHAIN_ID,
  hookAddress: parsed.HOOK_ADDRESS as `0x${string}`,
  vaultAddress: parsed.VAULT_ADDRESS as `0x${string}`,
  measurement: parsed.ATTESTATION_MEASUREMENT as `0x${string}`,
  attestorKey: parsed.ATTESTOR_PRIVATE_KEY as `0x${string}`,
  gatewayWebhookUrl: parsed.GATEWAY_WEBHOOK_URL,
  gatewayApiKey: parsed.GATEWAY_API_KEY ?? "",
  orderApiKey: parsed.ORDER_API_KEY ?? "",
  maxPendingOrders: parsed.MAX_PENDING_ORDERS,
  gatewayTimeoutMs: parsed.GATEWAY_TIMEOUT_MS,
  logLevel: parsed.LOG_LEVEL ?? "info",
  pythEndpoint: parsed.PYTH_ENDPOINT ?? undefined,
  pythTwapWindow: parsed.PYTH_TWAP_WINDOW ?? 300,
  pythPriceIds: parsePriceIdMap(parsed.PYTH_PRICE_IDS),
};

