export type SettlementPayload = {
  orderId: string;
  settlement: {
    orderId: `0x${string}`;
    poolId: `0x${string}`;
    trader: `0x${string}`;
    delta0: string;
    delta1: string;
    submittedAt: number;
    enclaveMeasurement: `0x${string}`;
  };
  attestation: {
    signature: `0x${string}`;
    digest: `0x${string}`;
    measurement: `0x${string}`;
  };
};

export type VerifiedSettlement = {
  clientOrderId: string;
  settlementOrderId: `0x${string}`;
  poolId: `0x${string}`;
  trader: `0x${string}`;
  delta0: bigint;
  delta1: bigint;
  submittedAt: number;
  signer: `0x${string}`;
};

