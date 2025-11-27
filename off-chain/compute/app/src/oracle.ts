import { HermesClient } from "@pythnetwork/hermes-client";
import { config } from "./config.js";
import { logger } from "./logger.js";

let hermesClient: HermesClient | undefined;

const PRICE_DECIMALS = 18;
const DEFAULT_TWAP_WINDOW = 300;

export type OraclePrice = {
  price: bigint;
  twap: bigint;
  publishTime: number;
  confidence: bigint;
};

export function initOracle() {
  if (!config.pythEndpoint) {
    logger.warn("Pyth endpoint not configured; oracle disabled");
    return;
  }
  hermesClient = new HermesClient(config.pythEndpoint, { timeout: 5000 });
  logger.info({ endpoint: config.pythEndpoint }, "Pyth oracle initialized");
}

export async function fetchOraclePrice(priceId: string): Promise<OraclePrice | null> {
  if (!hermesClient) {
    logger.warn("Oracle not initialized");
    return null;
  }

  try {
    const priceUpdate = await hermesClient.getLatestPriceUpdates([priceId], { parsed: true });
    const parsedPrice = priceUpdate.parsed?.[0];
    if (!parsedPrice) {
      logger.warn({ priceId }, "Price feed missing parsed data");
      return null;
    }

    const publishTime = parsedPrice.price.publish_time;
    const normalizedPrice = normalizePrice(parsedPrice.price.price, parsedPrice.price.expo);
    const confidence = normalizePrice(parsedPrice.price.conf, parsedPrice.price.expo);

    let twap = normalizedPrice;
    try {
      const window = config.pythTwapWindow ?? DEFAULT_TWAP_WINDOW;
      const twapResp = await hermesClient.getLatestTwaps([priceId], window, { parsed: true });
      const parsedTwap = twapResp.parsed?.[0];
      if (parsedTwap) {
        twap = normalizePrice(parsedTwap.twap.price, parsedTwap.twap.expo);
      }
    } catch (twapError) {
      logger.warn({ priceId, err: (twapError as Error).message }, "Failed to fetch TWAP; using spot price");
    }

    return {
      price: normalizedPrice,
      twap,
      publishTime,
      confidence,
    };
  } catch (error) {
    logger.error({ priceId, err: (error as Error).message }, "Failed to fetch price from Pyth");
    return null;
  }
}

function normalizePrice(rawPrice: string, exponent: number, targetDecimals: number = PRICE_DECIMALS): bigint {
  const price = BigInt(rawPrice);
  const scale = BigInt(targetDecimals + exponent);
  if (scale >= 0) {
    return price * 10n ** scale;
  }
  const divisor = 10n ** (-scale);
  return price / divisor;
}

export function calculateTwapDeviation(currentPrice: bigint, twapPrice: bigint): number {
  if (twapPrice === 0n) return 0;
  const priceDiff = currentPrice > twapPrice ? currentPrice - twapPrice : twapPrice - currentPrice;
  const deviationBps = Number((priceDiff * 10000n) / twapPrice);
  return deviationBps;
}

export function priceToSqrtPriceX96(price: bigint): bigint {
  if (price <= 0n) return 0n;
  const numerator = price * (1n << 192n);
  const scaled = numerator / 10n ** BigInt(PRICE_DECIMALS);
  return integerSqrt(scaled);
}

function integerSqrt(value: bigint): bigint {
  if (value === 0n) return 0n;
  let x0 = value;
  let x1 = (value + 1n) >> 1n;
  while (x1 < x0) {
    x0 = x1;
    x1 = (x1 + value / x1) >> 1n;
  }
  return x0;
}

