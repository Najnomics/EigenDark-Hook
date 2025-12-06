import { Hash, Hex, createWalletClient, defineChain, http } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { config } from "./config.js";
import { SettlementPayload, VerifiedSettlement } from "./types.js";
import { logger } from "./logger.js";

const hookAbi = [
  {
    inputs: [
      {
        components: [
          { name: "orderId", type: "bytes32" },
          { name: "poolId", type: "bytes32" },
          { name: "trader", type: "address" },
          { name: "delta0", type: "int128" },
          { name: "delta1", type: "int128" },
          { name: "submittedAt", type: "uint64" },
          { name: "enclaveMeasurement", type: "bytes32" },
          { name: "metadataHash", type: "bytes32" },
          { name: "sqrtPriceX96", type: "uint160" },
          { name: "twapDeviationBps", type: "uint64" },
          { name: "checkedLiquidity", type: "uint128" },
        ],
        name: "settlement",
        type: "tuple",
      },
      { name: "signature", type: "bytes" },
    ],
    name: "registerSettlement",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
] as const;

const chain =
  config.rpcUrl && config.chainId
    ? defineChain({
        id: config.chainId,
        name: "eigendark",
        network: "eigendark",
        nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
        rpcUrls: {
          default: { http: [config.rpcUrl] },
          public: { http: [config.rpcUrl] },
        },
      })
    : undefined;

const wallet =
  config.rpcUrl && config.submitterKey && chain
    ? createWalletClient({
        account: privateKeyToAccount(config.submitterKey as `0x${string}`),
        chain,
        transport: http(config.rpcUrl),
      })
    : undefined;

export function isSubmitterReady(): boolean {
  return Boolean(wallet);
}

export async function submitToHook(
  payload: SettlementPayload,
  verified: VerifiedSettlement,
): Promise<Hash | undefined> {
  if (!wallet) {
    logger.warn({ orderId: verified.settlementOrderId }, "Hook submitter not configured; skipping on-chain call");
    return undefined;
  }

  const txHash = await wallet.writeContract({
    address: config.hookAddress,
    abi: hookAbi,
    functionName: "registerSettlement",
    args: [
      {
        orderId: payload.settlement.orderId,
        poolId: payload.settlement.poolId,
        trader: payload.settlement.trader,
        delta0: BigInt(payload.settlement.delta0),
        delta1: BigInt(payload.settlement.delta1),
        submittedAt: BigInt(payload.settlement.submittedAt),
        enclaveMeasurement: payload.settlement.enclaveMeasurement,
        metadataHash: (payload.settlement.metadataHash ??
          ("0x" + "0".repeat(64))) as Hex,
        sqrtPriceX96: BigInt(payload.settlement.sqrtPriceX96 ?? "0"),
        twapDeviationBps: BigInt(payload.settlement.twapDeviationBps ?? 0),
        checkedLiquidity: BigInt(payload.settlement.checkedLiquidity ?? "0"),
      },
      payload.attestation.signature,
    ],
  });

  logger.info({ orderId: verified.settlementOrderId, txHash }, "Submitted settlement to hook");
  return txHash;
}

