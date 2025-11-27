import { randomUUID } from "crypto";
import { NextFunction, Request, Response } from "express";

export function attachRequestId(req: Request, res: Response, next: NextFunction) {
  const header = req.headers["x-request-id"];
  const requestId = typeof header === "string" && header.length > 0 ? header : randomUUID();
  req.requestId = requestId;
  res.setHeader("x-request-id", requestId);
  next();
}

