import axios from "axios";
export * from "./types.js";
export class EigenDarkClient {
    constructor(config) {
        if (!config.gatewayUrl) {
            throw new Error("gatewayUrl is required");
        }
        this.config = {
            gatewayUrl: config.gatewayUrl,
            computeUrl: config.computeUrl ?? "http://127.0.0.1:8080",
            timeoutMs: config.timeoutMs ?? 15000,
        };
        this.clientApiKey = config.clientApiKey;
        this.adminApiKey = config.adminApiKey;
        this.gateway = axios.create({
            baseURL: this.config.gatewayUrl,
            timeout: this.config.timeoutMs,
        });
    }
    setClientApiKey(key) {
        this.clientApiKey = key;
    }
    setAdminApiKey(key) {
        this.adminApiKey = key;
    }
    async health() {
        const [gateway, compute] = await Promise.allSettled([
            this.gateway.get("/health"),
            this.config.computeUrl
                ? axios.get(`${this.config.computeUrl}/health`, { timeout: this.config.timeoutMs })
                : Promise.resolve({ data: undefined }),
        ]);
        return {
            gateway: gateway.status === "fulfilled"
                ? gateway.value.data
                : { status: "error", timestamp: Date.now(), error: gateway.reason },
            compute: compute.status === "fulfilled"
                ? compute.value.data
                : this.config.computeUrl
                    ? { status: "error", timestamp: Date.now(), error: compute.reason }
                    : undefined,
        };
    }
    async submitOrder(order) {
        const response = await this.gateway.post("/orders", order, { headers: this.clientHeaders() });
        return response.data;
    }
    async getSettlement(orderId) {
        const response = await this.gateway.get(`/settlements/${orderId}`, { headers: this.clientHeaders() });
        return response.data;
    }
    async adminStats() {
        const response = await this.gateway.get("/admin/stats", { headers: this.adminHeaders() });
        return response.data;
    }
    async listPending(limit = 25) {
        const response = await this.gateway.get("/admin/settlements/pending", {
            headers: this.adminHeaders(),
            params: { limit },
        });
        return response.data;
    }
    async retrySettlements() {
        const response = await this.gateway.post("/admin/retry", undefined, { headers: this.adminHeaders() });
        return response.data;
    }
    async metrics() {
        const response = await this.gateway.get("/metrics", {
            headers: this.adminHeaders(),
            responseType: "text",
        });
        return response.data;
    }
    clientHeaders() {
        const headers = {};
        if (this.clientApiKey)
            headers["x-api-key"] = this.clientApiKey;
        return headers;
    }
    adminHeaders() {
        const headers = {};
        if (!this.adminApiKey) {
            throw new Error("ADMIN API key required for this operation. Set adminApiKey or provide ADMIN_API_KEY env var.");
        }
        headers["x-admin-key"] = this.adminApiKey;
        return headers;
    }
}
export function createEigenDarkClient(config) {
    return new EigenDarkClient(config);
}
