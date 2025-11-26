import "dotenv/config";

function requireEnv(key: string): string {
  const value = process.env[key];
  if (!value) {
    throw new Error(`Missing required environment variable ${key}`);
  }
  return value;
}

export const config = {
  port: Number(process.env.PORT ?? 8080),
  chainId: Number(process.env.CHAIN_ID ?? 11155111),
  hookAddress: requireEnv("HOOK_ADDRESS") as `0x${string}`,
  vaultAddress: requireEnv("VAULT_ADDRESS") as `0x${string}`,
  measurement: requireEnv("ATTESTATION_MEASUREMENT") as `0x${string}`,
  attestorKey: requireEnv("ATTESTOR_PRIVATE_KEY") as `0x${string}`,
  gatewayWebhookUrl: requireEnv("GATEWAY_WEBHOOK_URL"),
  gatewayApiKey: process.env.GATEWAY_API_KEY ?? "",
};

