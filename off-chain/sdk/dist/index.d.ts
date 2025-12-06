import { EigenDarkClientConfig, HealthStatus, OrderRequest, RetrySummary, SettlementRecord } from "./types.js";
export * from "./types.js";
export declare class EigenDarkClient {
    private readonly config;
    private clientApiKey?;
    private adminApiKey?;
    private readonly gateway;
    constructor(config: EigenDarkClientConfig);
    setClientApiKey(key: string): void;
    setAdminApiKey(key: string): void;
    health(): Promise<{
        gateway: HealthStatus;
        compute?: HealthStatus;
    }>;
    submitOrder(order: OrderRequest): Promise<any>;
    getSettlement(orderId: string): Promise<SettlementRecord>;
    adminStats(): Promise<any>;
    listPending(limit?: number): Promise<{
        count: number;
        settlements: SettlementRecord[];
    }>;
    retrySettlements(): Promise<RetrySummary>;
    metrics(): Promise<string>;
    private clientHeaders;
    private adminHeaders;
}
export declare function createEigenDarkClient(config: EigenDarkClientConfig): EigenDarkClient;
