import { promises as fs } from "fs";
import path from "path";
import { config } from "./config.js";
import { SettlementPayload, VerifiedSettlement } from "./types.js";

export type StoredSettlement = {
  clientOrderId: string;
  payload: SettlementPayload;
  verified: VerifiedSettlement;
  status: "verified" | "submitted" | "failed";
  lastAttemptAt?: number;
  txHash?: string;
  error?: string;
};

export type SerializableSettlement = Omit<StoredSettlement, "verified"> & {
  verified: Omit<VerifiedSettlement, "delta0" | "delta1"> & {
    delta0: string;
    delta1: string;
  };
};

const store = new Map<string, StoredSettlement>();
const storePath = path.join(config.storageDir, "settlements.json");
let persistTimer: NodeJS.Timeout | undefined;

export async function initSettlementStore() {
  await fs.mkdir(config.storageDir, { recursive: true });
  try {
    const raw = await fs.readFile(storePath, "utf8");
    const parsed: SerializableSettlement[] = JSON.parse(raw);
    parsed.forEach((entry) => {
      store.set(entry.clientOrderId, deserialize(entry));
    });
  } catch (error: any) {
    if (error.code !== "ENOENT") {
      console.warn("Failed to load settlement store", error);
    }
  }
}

export function upsertSettlement(payload: SettlementPayload, verified: VerifiedSettlement): StoredSettlement {
  const next: StoredSettlement = {
    clientOrderId: payload.orderId,
    payload,
    verified,
    status: "verified",
  };
  store.set(next.clientOrderId, next);
  schedulePersist();
  return next;
}

export function getSettlement(orderId: string): StoredSettlement | undefined {
  return store.get(orderId);
}

export function listPendingSettlements(): StoredSettlement[] {
  return Array.from(store.values()).filter((entry) => entry.status !== "submitted");
}

export function markSubmitted(orderId: string, txHash?: string) {
  const entry = store.get(orderId);
  if (!entry) return;
  entry.status = "submitted";
  entry.txHash = txHash;
  entry.lastAttemptAt = Date.now();
  entry.error = undefined;
  schedulePersist();
}

export function markFailed(orderId: string, error: string) {
  const entry = store.get(orderId);
  if (!entry) return;
  entry.status = "failed";
  entry.error = error;
  entry.lastAttemptAt = Date.now();
  schedulePersist();
}

function schedulePersist() {
  if (persistTimer) return;
  persistTimer = setTimeout(async () => {
    persistTimer = undefined;
    await persistStore();
  }, 200);
}

async function persistStore() {
  const serializable: SerializableSettlement[] = Array.from(store.values()).map(serializeSettlement);
  const payload = JSON.stringify(serializable, null, 2);
  try {
    await fs.writeFile(storePath, payload, "utf8");
  } catch (error) {
    console.error("Failed to persist settlement store", error);
  }
}

export function serializeSettlement(entry: StoredSettlement): SerializableSettlement {
  return {
    ...entry,
    verified: {
      ...entry.verified,
      delta0: entry.verified.delta0.toString(),
      delta1: entry.verified.delta1.toString(),
    },
  };
}

function deserialize(entry: SerializableSettlement): StoredSettlement {
  return {
    ...entry,
    verified: {
      ...entry.verified,
      delta0: BigInt(entry.verified.delta0),
      delta1: BigInt(entry.verified.delta1),
    },
  };
}

