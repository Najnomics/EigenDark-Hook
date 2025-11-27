import { NextFunction, Request, Response } from "express";
import { config } from "./config.js";

export function requireGatewayAuth(req: Request, res: Response, next: NextFunction) {
  if (!config.orderApiKey) {
    return next();
  }

  if (req.headers["x-api-key"] !== config.orderApiKey) {
    return res.status(401).json({ error: "invalid api key" });
  }

  return next();
}

