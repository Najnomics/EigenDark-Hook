import { createWalletClient, http, Hex } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { sepolia } from "viem/chains";
import { config } from "./config.js";
import { SettlementInstruction, SettlementAttestation } from "./types.js";

const account = privateKeyToAccount(config.attestorKey as Hex);
const chain = sepolia;

const wallet = createWalletClient({
  account,
  chain,
  transport: http(),
});

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
};

export async function signSettlement(settlement: SettlementInstruction): Promise<SettlementAttestation> {
  const domain = {
    name: "EigenDarkSettlement",
    version: "0.1",
    chainId: BigInt(config.chainId),
    verifyingContract: config.hookAddress,
  } as const;

  const signature = await wallet.signTypedData({
    account,
    domain,
    types: settlementTypes,
    primaryType: "Settlement",
    message: {
      orderId: settlement.orderId,
      poolId: settlement.poolId,
      trader: settlement.trader,
      delta0: settlement.delta0,
      delta1: settlement.delta1,
      submittedAt: BigInt(settlement.submittedAt),
      enclaveMeasurement: settlement.enclaveMeasurement,
      metadataHash: settlement.metadataHash,
      sqrtPriceX96: settlement.sqrtPriceX96,
      twapDeviationBps: BigInt(settlement.twapDeviationBps),
      checkedLiquidity: settlement.checkedLiquidity,
    },
  });

  return {
    measurement: settlement.enclaveMeasurement,
    signature,
    digest: signature,
  };
}

