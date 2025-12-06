import axios, { AxiosInstance } from "axios";
import {
  EigenDarkClientConfig,
  HealthStatus,
  OrderRequest,
  RetrySummary,
  SettlementRecord,
} from "./types.js";

export * from "./types.js";

type InternalConfig = {
  gatewayUrl: string;
  computeUrl: string;
  timeoutMs: number;
};

export class EigenDarkClient {
  private readonly config: InternalConfig;
  private clientApiKey?: string;
  private adminApiKey?: string;
  private readonly gateway: AxiosInstance;

  constructor(config: EigenDarkClientConfig) {
    if (!config.gatewayUrl) {
      throw new Error("gatewayUrl is required");
    }

    this.config = {
      gatewayUrl: config.gatewayUrl,
      computeUrl: config.computeUrl ?? "http://127.0.0.1:8080",
      timeoutMs: config.timeoutMs ?? 15_000,
    };
    this.clientApiKey = config.clientApiKey;
    this.adminApiKey = config.adminApiKey;

    this.gateway = axios.create({
      baseURL: this.config.gatewayUrl,
      timeout: this.config.timeoutMs,
    });
  }

  public setClientApiKey(key: string) {
    this.clientApiKey = key;
  }

  public setAdminApiKey(key: string) {
    this.adminApiKey = key;
  }

  public async health(): Promise<{ gateway: HealthStatus; compute?: HealthStatus }> {
    const [gateway, compute] = await Promise.allSettled([
      this.gateway.get<HealthStatus>("/health"),
      this.config.computeUrl
        ? axios.get<HealthStatus>(`${this.config.computeUrl}/health`, { timeout: this.config.timeoutMs })
        : Promise.resolve({ data: undefined } as any),
    ]);

    return {
      gateway:
        gateway.status === "fulfilled"
          ? gateway.value.data
          : { status: "error", timestamp: Date.now(), error: gateway.reason },
      compute:
        compute.status === "fulfilled"
          ? compute.value.data
          : this.config.computeUrl
            ? { status: "error", timestamp: Date.now(), error: compute.reason }
            : undefined,
    };
  }

  public async submitOrder(order: OrderRequest) {
    const response = await this.gateway.post("/orders", order, { headers: this.clientHeaders() });
    return response.data;
  }

  public async getSettlement(orderId: string): Promise<SettlementRecord> {
    const response = await this.gateway.get(`/settlements/${orderId}`, { headers: this.clientHeaders() });
    return response.data;
  }

  public async adminStats() {
    const response = await this.gateway.get("/admin/stats", { headers: this.adminHeaders() });
    return response.data;
  }

  public async listPending(limit = 25): Promise<{ count: number; settlements: SettlementRecord[] }> {
    const response = await this.gateway.get("/admin/settlements/pending", {
      headers: this.adminHeaders(),
      params: { limit },
    });
    return response.data;
  }

  public async retrySettlements(): Promise<RetrySummary> {
    const response = await this.gateway.post("/admin/retry", undefined, { headers: this.adminHeaders() });
    return response.data;
  }

  public async metrics(): Promise<string> {
    const response = await this.gateway.get("/metrics", {
      headers: this.adminHeaders(),
      responseType: "text",
    });
    return response.data;
  }

  private clientHeaders() {
    const headers: Record<string, string> = {};
    if (this.clientApiKey) headers["x-api-key"] = this.clientApiKey;
    return headers;
  }

  private adminHeaders() {
    const headers: Record<string, string> = {};
    if (!this.adminApiKey) {
      throw new Error("ADMIN API key required for this operation. Set adminApiKey or provide ADMIN_API_KEY env var.");
    }
    headers["x-admin-key"] = this.adminApiKey;
    return headers;
  }
}

export function createEigenDarkClient(config: EigenDarkClientConfig) {
  return new EigenDarkClient(config);
}

