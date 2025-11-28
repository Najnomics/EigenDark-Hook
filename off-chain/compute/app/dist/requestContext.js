import { randomUUID } from "crypto";
export function attachRequestId(req, res, next) {
    const header = req.headers["x-request-id"];
    const requestId = typeof header === "string" && header.length > 0 ? header : randomUUID();
    req.requestId = requestId;
    res.setHeader("x-request-id", requestId);
    next();
}
