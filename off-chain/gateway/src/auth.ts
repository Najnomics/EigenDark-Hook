import { NextFunction, Request, Response } from "express";
import { config } from "./config.js";

export function requireClientAuth(req: Request, res: Response, next: NextFunction) {
  if (!config.clientApiKey) {
    return next();
  }

  const header = req.headers["x-api-key"];
  if (header !== config.clientApiKey) {
    return res.status(401).json({ error: "invalid client api key" });
  }

  return next();
}

