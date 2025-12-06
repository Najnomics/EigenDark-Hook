import { Hex, recoverTypedDataAddress } from "viem";
import { config } from "./config.js";
import { SettlementPayload, VerifiedSettlement } from "./types.js";

const settlementTypes = {
  Settlement: [
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
} as const;

const domain = {
  name: "EigenDarkSettlement",
  version: "0.1",
  chainId: BigInt(config.chainId),
  verifyingContract: config.hookAddress,
} as const;

export async function verifySettlement(payload: SettlementPayload): Promise<VerifiedSettlement> {
  if (payload.attestation.measurement.toLowerCase() !== config.measurement.toLowerCase()) {
    throw new Error("measurement mismatch");
  }

  const message = {
    orderId: payload.settlement.orderId,
    poolId: payload.settlement.poolId,
    trader: payload.settlement.trader,
    delta0: BigInt(payload.settlement.delta0),
    delta1: BigInt(payload.settlement.delta1),
    submittedAt: BigInt(payload.settlement.submittedAt),
    enclaveMeasurement: payload.settlement.enclaveMeasurement,
    metadataHash: payload.settlement.metadataHash || ("0x" + "0".repeat(64)) as Hex,
    sqrtPriceX96: BigInt(payload.settlement.sqrtPriceX96 || "0"),
    twapDeviationBps: BigInt(payload.settlement.twapDeviationBps || 0),
    checkedLiquidity: BigInt(payload.settlement.checkedLiquidity || "0"),
  } as const;
  const signer = await recoverTypedDataAddress({
    domain,
    types: settlementTypes,
    primaryType: "Settlement",
    message,
    signature: payload.attestation.signature,
  });

  return {
    clientOrderId: payload.orderId,
    settlementOrderId: message.orderId,
    poolId: message.poolId,
    trader: message.trader,
    delta0: message.delta0,
    delta1: message.delta1,
    submittedAt: Number(message.submittedAt),
    signer: signer as Hex,
  };
}

