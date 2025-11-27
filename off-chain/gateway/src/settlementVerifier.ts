import { recoverTypedDataAddress } from "viem";
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

  const message = payload.settlement;
  const signer = await recoverTypedDataAddress({
    domain,
    types: settlementTypes,
    primaryType: "Settlement",
    message,
    signature: payload.attestation.signature,
  });

  return {
    orderId: payload.orderId,
    poolId: message.poolId,
    trader: message.trader,
    delta0: BigInt(message.delta0),
    delta1: BigInt(message.delta1),
    submittedAt: message.submittedAt,
    signer,
  };
}

