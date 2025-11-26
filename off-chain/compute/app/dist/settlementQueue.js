import { randomUUID } from "crypto";
export class SettlementQueue {
    items = new Map();
    listeners = [];
    enqueue(order) {
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
    onChange(listener) {
        this.listeners.push(listener);
    }
    notify(item) {
        for (const listener of this.listeners) {
            listener(item);
        }
    }
}
