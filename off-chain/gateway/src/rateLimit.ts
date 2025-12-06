import rateLimit, { ipKeyGenerator } from "express-rate-limit";
import type { Request, RequestHandler } from "express";
import { config } from "./config.js";

function keyFromRequest(req: Request) {
  const apiKey = req.headers["x-api-key"] as string | undefined;
  return apiKey && apiKey.length > 0 ? apiKey : ipKeyGenerator(req.ip ?? "");
}

function adminKeyFromRequest(req: Request) {
  const adminKey = (req.headers["x-admin-key"] as string | undefined) ?? (req.headers["x-api-key"] as string | undefined);
  return adminKey && adminKey.length > 0 ? adminKey : ipKeyGenerator(req.ip ?? "");
}

const baseOptions = {
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: "rate_limit_exceeded" },
};

const noopRateLimiter: RequestHandler = (_req, _res, next) => next();

export const orderRateLimiter =
  config.orderRateMax > 0
    ? rateLimit({
        ...baseOptions,
        windowMs: config.orderRateWindowMs,
        limit: config.orderRateMax,
        keyGenerator: keyFromRequest,
      })
    : noopRateLimiter;

export const adminRateLimiter =
  config.adminRateMax > 0
    ? rateLimit({
        ...baseOptions,
        windowMs: config.adminRateWindowMs,
        limit: config.adminRateMax,
        keyGenerator: adminKeyFromRequest,
      })
    : noopRateLimiter;


