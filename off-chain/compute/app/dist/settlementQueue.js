import { randomUUID } from "crypto";
export class SettlementQueue {
    capacity;
    items = new Map();
    listeners = [];
    constructor(capacity = Infinity) {
        this.capacity = capacity;
    }
    enqueue(order) {
        if (this.items.size >= this.capacity) {
            throw new Error("order queue at capacity");
        }
        const entry = {
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
    markProcessing(orderId) {
        const item = this.items.get(orderId);
        if (!item)
            return;
        item.status = "processing";
        this.notify(item);
    }
    markSettled(orderId, envelope) {
        const item = this.items.get(orderId);
        if (!item)
            return;
        item.status = "settled";
        item.settlement = envelope;
        this.notify(item);
    }
    markFailed(orderId, error) {
        const item = this.items.get(orderId);
        if (!item)
            return;
        item.status = "failed";
        item.error = error;
        this.notify(item);
    }
    get(orderId) {
        return this.items.get(orderId);
    }
    size() {
        return this.items.size;
    }
    stats() {
        const summary = { queued: 0, processing: 0, settled: 0, failed: 0 };
        for (const item of this.items.values()) {
            summary[item.status] += 1;
        }
        return summary;
    }
    onChange(listener) {
        this.listeners.push(listener);
    }
    notify(item) {
        for (const listener of this.listeners) {
            listener(item);
        }
    }
}
