import { randomUUID } from "crypto";
import { EncryptedOrder, QueueItem, SettlementEnvelope } from "./types.js";

type Listener = (item: QueueItem) => void;

export class SettlementQueue {
  private items = new Map<string, QueueItem>();
  private listeners: Listener[] = [];

  enqueue(order: Omit<EncryptedOrder, "orderId" | "receivedAt">): QueueItem {
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

  onChange(listener: Listener) {
    this.listeners.push(listener);
  }

  private notify(item: QueueItem) {
    for (const listener of this.listeners) {
      listener(item);
    }
  }
}

