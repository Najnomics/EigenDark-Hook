import express from "express";
import { z } from "zod";
import axios from "axios";
import { keccak256, stringToHex, parseUnits, encodeAbiParameters } from "viem";
import { config } from "./config.js";
import { SettlementQueue } from "./settlementQueue.js";
import { signSettlement } from "./attestation.js";
import { logger } from "./logger.js";
import { attachRequestId } from "./requestContext.js";
import { requireGatewayAuth } from "./auth.js";
import { initOracle, fetchOraclePrice, calculateTwapDeviation, priceToSqrtPriceX96 } from "./oracle.js";
const app = express();
const queue = new SettlementQueue(config.maxPendingOrders);
app.use(express.json({ limit: "1mb" }));
app.use(attachRequestId);
app.use((req, res, next) => {
    const start = Date.now();
    res.on("finish", () => {
        logger.info({
            reqId: req.requestId,
            method: req.method,
            path: req.path,
            status: res.statusCode,
            durationMs: Date.now() - start,
        }, "request completed");
    });
    next();
});
const address = z.string().regex(/^0x[0-9a-fA-F]{40}$/, "invalid address");
const decimalString = z
    .string()
    .regex(/^\d+(\.\d+)?$/, "must be a positive decimal string")
    .refine((val) => Number(val) > 0, "value must be positive");
const orderSchema = z
    .object({
    trader: address,
    tokenIn: address,
    tokenOut: address,
    amount: decimalString,
    limitPrice: decimalString,
    payload: z.string().min(1),
})
    .refine((order) => order.tokenIn.toLowerCase() !== order.tokenOut.toLowerCase(), {
    message: "tokenIn and tokenOut must differ",
    path: ["tokenOut"],
});
app.get("/health", (_req, res) => {
    res.json({
        status: "ok",
        measurement: config.measurement,
        hook: config.hookAddress,
        pendingOrders: queue.size(),
        timestamp: Date.now(),
    });
});
app.get("/orders/:orderId", (req, res) => {
    const order = queue.get(req.params.orderId);
    if (!order) {
        return res.status(404).json({ error: "order not found" });
    }
    res.json(order);
});
app.get("/metrics", (_req, res) => {
    const stats = queue.stats();
    res.json({
        pending: queue.size(),
        stats,
    });
});
app.post("/orders", requireGatewayAuth, async (req, res) => {
    const parsed = orderSchema.safeParse(req.body);
    if (!parsed.success) {
        return res.status(400).json({ error: parsed.error.flatten() });
    }
    if (queue.size() >= config.maxPendingOrders) {
        logger.warn({ reqId: req.requestId }, "order queue at capacity");
        return res.status(503).json({ error: "order_queue_full" });
    }
    const entry = queue.enqueue(parsed.data);
    processOrder(entry.order).catch((err) => {
        const message = err.message;
        logger.error({ orderId: entry.order.orderId, err: message }, "order processing failed");
        queue.markFailed(entry.order.orderId, message);
    });
    res.status(202).json({ orderId: entry.order.orderId, status: entry.status });
});
queue.onChange((item) => {
    logger.info({ orderId: item.order.orderId, status: item.status }, "queue status update");
    if (item.status === "settled" && item.settlement) {
        notifyGateway(item).catch((err) => {
            logger.error({ orderId: item.order.orderId, err: err.message }, "failed to notify gateway");
        });
    }
});
async function processOrder(order) {
    queue.markProcessing(order.orderId);
    try {
        const priceId = getPriceIdForPair(order.tokenIn, order.tokenOut);
        const oraclePrice = priceId ? await fetchOraclePrice(priceId) : null;
        const fallbackPrice = parseUnits(order.limitPrice, 18);
        const executionPrice = oraclePrice?.price ?? fallbackPrice;
        const twapPrice = oraclePrice?.twap ?? executionPrice;
        const twapDeviationBps = oraclePrice ? calculateTwapDeviation(executionPrice, twapPrice) : 0;
        const settlement = buildSettlement(order, executionPrice, twapPrice, twapDeviationBps);
        const attestation = await signSettlement(settlement);
        queue.markSettled(order.orderId, { settlement, attestation });
    }
    catch (error) {
        const message = error.message;
        logger.error({ orderId: order.orderId, err: message }, "order processing failed");
        queue.markFailed(order.orderId, message);
        throw error;
    }
}
function getPriceIdForPair(tokenIn, tokenOut) {
    const pair = `${tokenIn.toLowerCase()}-${tokenOut.toLowerCase()}`;
    return config.pythPriceIds[pair] ?? null;
}
function buildSettlement(order, executionPrice, twapPrice, twapDeviationBps) {
    // Generate poolId using Uniswap V4 PoolKey structure
    // PoolKey = (currency0, currency1, fee, tickSpacing, hooks)
    // We use default Uniswap V4 values: fee=3000 (0.3%), tickSpacing=60
    const currency0 = order.tokenIn.toLowerCase();
    const currency1 = order.tokenOut.toLowerCase();
    const fee = 3000; // 0.3% fee tier
    const tickSpacing = 60; // Standard tick spacing for 0.3% fee
    const hooks = config.hookAddress;
    // Encode PoolKey as Solidity would: abi.encode(currency0, currency1, fee, tickSpacing, hooks)
    const poolKeyEncoded = encodeAbiParameters([
        { type: "address", name: "currency0" },
        { type: "address", name: "currency1" },
        { type: "uint24", name: "fee" },
        { type: "int24", name: "tickSpacing" },
        { type: "address", name: "hooks" },
    ], [currency0, currency1, fee, tickSpacing, hooks]);
    const poolId = keccak256(poolKeyEncoded);
    const orderHash = keccak256(stringToHex(order.orderId));
    const amountIn = parseUnits(order.amount, 18);
    // Calculate delta1 (amount out) with proper decimal handling
    // executionPrice is already in 18 decimals, so we need to scale properly
    // delta1 = (amountIn * executionPrice) / 10^18
    // But we need to ensure it fits in int128
    const amountOutRaw = (amountIn * executionPrice) / 10n ** 18n;
    // Ensure values fit in int128 range
    const delta0 = toInt128(-amountIn);
    const delta1 = toInt128(amountOutRaw);
    const metadataHash = keccak256(stringToHex(`${order.orderId}-${order.trader}-${order.amount}-${order.limitPrice}`));
    const sqrtPriceX96 = priceToSqrtPriceX96(executionPrice);
    const checkedLiquidity = amountIn * 10n;
    return {
        orderId: orderHash,
        poolId,
        trader: order.trader,
        delta0,
        delta1,
        submittedAt: Math.floor(Date.now() / 1000),
        enclaveMeasurement: config.measurement,
        metadataHash,
        sqrtPriceX96,
        twapDeviationBps,
        checkedLiquidity,
    };
}
function toInt128(value) {
    const min = -(2n ** 127n);
    const max = 2n ** 127n - 1n;
    if (value < min || value > max) {
        throw new Error("Value exceeds int128 range");
    }
    return value;
}
async function notifyGateway(item) {
    if (!item.settlement)
        return;
    // Serialize BigInt values to strings for JSON
    const settlement = item.settlement.settlement;
    const serializedSettlement = {
        orderId: settlement.orderId,
        poolId: settlement.poolId,
        trader: settlement.trader,
        delta0: settlement.delta0.toString(),
        delta1: settlement.delta1.toString(),
        submittedAt: settlement.submittedAt,
        enclaveMeasurement: settlement.enclaveMeasurement,
        metadataHash: settlement.metadataHash,
        sqrtPriceX96: settlement.sqrtPriceX96.toString(),
        twapDeviationBps: settlement.twapDeviationBps,
        checkedLiquidity: settlement.checkedLiquidity.toString(),
    };
    const headers = {};
    if (config.gatewayApiKey) {
        headers["x-api-key"] = config.gatewayApiKey;
    }
    await axios.post(config.gatewayWebhookUrl, {
        orderId: item.order.orderId,
        settlement: serializedSettlement,
        attestation: item.settlement.attestation,
    }, {
        headers,
        timeout: config.gatewayTimeoutMs,
    });
    logger.info({ orderId: item.order.orderId }, "pushed settlement to gateway");
}
// Initialize oracle on startup
initOracle();
const port = config.port;
app.listen(port, "0.0.0.0", () => {
    logger.info({ port: config.port, measurement: config.measurement }, "EigenDark EigenCompute app listening");
});
