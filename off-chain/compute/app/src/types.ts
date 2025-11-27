export type EncryptedOrder = {
  orderId: string;
  trader: string;
  tokenIn: string;
  tokenOut: string;
  amount: string;
  limitPrice: string;
  payload: string;
  receivedAt: number;
};

export type SettlementInstruction = {
  orderId: `0x${string}`;
  poolId: `0x${string}`;
  trader: string;
  delta0: bigint;
  delta1: bigint;
  submittedAt: number;
  enclaveMeasurement: `0x${string}`;
};

export type SettlementAttestation = {
  measurement: `0x${string}`;
  signature: `0x${string}`;
  digest: `0x${string}`;
};

export type SettlementEnvelope = {
  settlement: SettlementInstruction;
  attestation: SettlementAttestation;
};

export type QueueItem = {
  order: EncryptedOrder;
  status: "queued" | "processing" | "settled" | "failed";
  error?: string;
  settlement?: SettlementEnvelope;
};

export type AttestationConfig = {
  hookAddress: `0x${string}`;
  chainId: number;
  measurement: `0x${string}`;
  attestorKey: `0x${string}`;
};

