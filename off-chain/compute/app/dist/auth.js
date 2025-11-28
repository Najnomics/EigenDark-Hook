import { config } from "./config.js";
export function requireGatewayAuth(req, res, next) {
    if (!config.orderApiKey) {
        return next();
    }
    if (req.headers["x-api-key"] !== config.orderApiKey) {
        return res.status(401).json({ error: "invalid api key" });
    }
    return next();
}
