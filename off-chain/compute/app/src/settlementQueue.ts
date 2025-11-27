import { randomUUID } from "crypto";
import { EncryptedOrder, QueueItem, SettlementEnvelope } from "./types.js";

type Listener = (item: QueueItem) => void;

export type QueueStats = {
  queued: number;
  processing: number;
  settled: number;
  failed: number;
};

export class SettlementQueue {
  private items = new Map<string, QueueItem>();
  private listeners: Listener[] = [];

  constructor(private readonly capacity: number = Infinity) {}

  enqueue(order: Omit<EncryptedOrder, "orderId" | "receivedAt">): QueueItem {
    if (this.items.size >= this.capacity) {
      throw new Error("order queue at capacity");
    }

    const entry: QueueItem = {
      order: {
        ...order,
        orderId: randomUUID(),
        receivedAt: Date.now(),
      },
      status: "queued",
    };
    this.items.set(entry.order.orderId, entry);
    this.notify(entry);
    return entry;
  }

  markProcessing(orderId: string) {
    const item = this.items.get(orderId);
    if (!item) return;
    item.status = "processing";
    this.notify(item);
  }

  markSettled(orderId: string, envelope: SettlementEnvelope) {
    const item = this.items.get(orderId);
    if (!item) return;
    item.status = "settled";
    item.settlement = envelope;
    this.notify(item);
  }

  markFailed(orderId: string, error: string) {
    const item = this.items.get(orderId);
    if (!item) return;
    item.status = "failed";
    item.error = error;
    this.notify(item);
  }

  get(orderId: string) {
    return this.items.get(orderId);
  }

  size() {
    return this.items.size;
  }

  stats(): QueueStats {
    const summary: QueueStats = { queued: 0, processing: 0, settled: 0, failed: 0 };
    for (const item of this.items.values()) {
      summary[item.status] += 1;
    }
    return summary;
  }

  onChange(listener: Listener) {
    this.listeners.push(listener);
  }

  private notify(item: QueueItem) {
    for (const listener of this.listeners) {
      listener(item);
    }
  }
}

