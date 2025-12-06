import rateLimit from "express-rate-limit";
import type { Request, RequestHandler } from "express";
import { config } from "./config.js";

function keyFromRequest(req: Request) {
  return ((req.headers["x-api-key"] as string | undefined) ?? req.ip ?? "anon").toString();
}

function adminKeyFromRequest(req: Request) {
  return ((req.headers["x-admin-key"] as string | undefined) ??
    (req.headers["x-api-key"] as string | undefined) ??
    req.ip ??
    "anon"
  ).toString();
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


