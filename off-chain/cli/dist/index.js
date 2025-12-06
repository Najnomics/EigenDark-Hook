#!/usr/bin/env node
import { Command } from "commander";
import chalk from "chalk";
import axios from "axios";
import { config as loadEnv } from "dotenv";
import { readFile } from "fs/promises";
loadEnv();
function resolveConfig(overrides) {
    return {
        gatewayUrl: overrides?.gatewayUrl ?? process.env.GATEWAY_URL ?? "http://127.0.0.1:4000",
        computeUrl: overrides?.computeUrl ?? process.env.COMPUTE_URL ?? "http://127.0.0.1:8080",
        apiKey: overrides?.apiKey ?? process.env.CLIENT_API_KEY,
        adminKey: overrides?.adminKey ?? process.env.ADMIN_API_KEY ?? process.env.CLIENT_API_KEY,
    };
}
function createGatewayClient(cfg, admin = false) {
    const headers = {};
    if (admin) {
        if (cfg.adminKey)
            headers["x-admin-key"] = cfg.adminKey;
    }
    else if (cfg.apiKey) {
        headers["x-api-key"] = cfg.apiKey;
    }
    return axios.create({
        baseURL: cfg.gatewayUrl,
        timeout: 15_000,
        headers,
    });
}
async function printJson(label, data) {
    console.log(chalk.cyanBright(`\n${label}`));
    console.log(JSON.stringify(data, null, 2));
}
const program = new Command();
program
    .name("eigendark")
    .description("EigenDark CLI for traders, LPs, and operators")
    .version("0.1.0");
program
    .command("health")
    .description("Check gateway + compute health")
    .option("--gateway-url <url>")
    .option("--compute-url <url>")
    .option("--api-key <key>")
    .action(async (opts) => {
    const cfg = resolveConfig(opts);
    const gatewayClient = createGatewayClient(cfg);
    try {
        const [gatewayRes, computeRes] = await Promise.all([
            gatewayClient.get("/health"),
            axios.get(`${cfg.computeUrl}/health`, { timeout: 10_000 }),
        ]);
        await printJson("Gateway", gatewayRes.data);
        await printJson("Compute", computeRes.data);
        console.log(chalk.green("\nAll systems healthy ✅"));
    }
    catch (error) {
        console.error(chalk.red("Health check failed"), error instanceof Error ? error.message : error);
        process.exitCode = 1;
    }
});
const orderCmd = program.command("orders").description("Manage confidential orders");
orderCmd
    .command("submit")
    .requiredOption("--trader <address>", "Trader address")
    .requiredOption("--token-in <address>", "Token in address")
    .requiredOption("--token-out <address>", "Token out address")
    .requiredOption("--amount <decimal>", "Amount as decimal string (e.g. 1.0)")
    .requiredOption("--limit-price <decimal>", "Limit price (decimal string)")
    .option("--payload <string>", "Encrypted payload string")
    .option("--payload-file <path>", "Load encrypted payload from file")
    .option("--gateway-url <url>")
    .option("--api-key <key>")
    .action(async (opts) => {
    const cfg = resolveConfig(opts);
    const payload = await resolvePayload(opts.payload, opts.payloadFile);
    const client = createGatewayClient(cfg);
    try {
        const response = await client.post("/orders", {
            trader: opts.trader,
            tokenIn: opts["tokenIn"] ?? opts.tokenIn,
            tokenOut: opts["tokenOut"] ?? opts.tokenOut,
            amount: opts.amount,
            limitPrice: opts["limitPrice"] ?? opts.limitPrice,
            payload,
        });
        console.log(chalk.green("Order accepted"));
        await printJson("Response", response.data);
    }
    catch (error) {
        const message = error?.response?.data ?? error.message ?? String(error);
        console.error(chalk.red("Order submission failed:"), message);
        process.exitCode = 1;
    }
});
orderCmd
    .command("status <orderId>")
    .description("Fetch settlement info for orderId (client ID)")
    .option("--gateway-url <url>")
    .option("--api-key <key>")
    .action(async (orderId, opts) => {
    const cfg = resolveConfig(opts);
    const client = createGatewayClient(cfg);
    try {
        const response = await client.get(`/settlements/${orderId}`);
        await printJson("Settlement", response.data);
    }
    catch (error) {
        console.error(chalk.yellow("Settlement not available"), error?.response?.data ?? error.message);
        process.exitCode = 1;
    }
});
const adminCmd = program.command("gateway").description("Gateway admin utilities");
adminCmd
    .command("stats")
    .description("Show gateway stats")
    .option("--gateway-url <url>")
    .option("--admin-key <key>")
    .action(async (opts) => {
    const cfg = resolveConfig({ ...opts, adminKey: opts.adminKey });
    const client = createGatewayClient(cfg, true);
    try {
        const response = await client.get("/admin/stats");
        await printJson("Stats", response.data);
    }
    catch (error) {
        console.error(chalk.red("Failed to fetch stats"), error?.response?.data ?? error.message);
        process.exitCode = 1;
    }
});
adminCmd
    .command("pending")
    .description("List pending settlements awaiting submission")
    .option("--limit <n>", "Result limit", "25")
    .option("--gateway-url <url>")
    .option("--admin-key <key>")
    .action(async (opts) => {
    const cfg = resolveConfig({ ...opts, adminKey: opts.adminKey });
    const client = createGatewayClient(cfg, true);
    try {
        const response = await client.get("/admin/settlements/pending", {
            params: { limit: Number(opts.limit ?? 25) },
        });
        await printJson("Pending Settlements", response.data);
    }
    catch (error) {
        console.error(chalk.red("Failed to list settlements"), error?.response?.data ?? error.message);
        process.exitCode = 1;
    }
});
adminCmd
    .command("retry")
    .description("Trigger immediate settlement retry cycle")
    .option("--gateway-url <url>")
    .option("--admin-key <key>")
    .action(async (opts) => {
    const cfg = resolveConfig({ ...opts, adminKey: opts.adminKey });
    const client = createGatewayClient(cfg, true);
    try {
        const response = await client.post("/admin/retry");
        await printJson("Retry Summary", response.data);
    }
    catch (error) {
        console.error(chalk.red("Retry failed"), error?.response?.data ?? error.message);
        process.exitCode = 1;
    }
});
adminCmd
    .command("metrics")
    .description("Stream Prometheus metrics")
    .option("--gateway-url <url>")
    .option("--admin-key <key>")
    .action(async (opts) => {
    const cfg = resolveConfig({ ...opts, adminKey: opts.adminKey });
    const client = createGatewayClient(cfg, true);
    try {
        const response = await client.get("/metrics", { responseType: "text" });
        console.log(response.data);
    }
    catch (error) {
        console.error(chalk.red("Metrics unavailable"), error?.response?.data ?? error.message);
        process.exitCode = 1;
    }
});
program.parseAsync().catch((error) => {
    console.error(chalk.red("Unexpected CLI error"), error);
    process.exit(1);
});
async function resolvePayload(inline, filePath) {
    if (inline)
        return inline;
    if (filePath) {
        return (await readFile(filePath, "utf8")).trim();
    }
    const defaultPayload = process.env.EIGENDARK_PAYLOAD;
    if (defaultPayload)
        return defaultPayload;
    throw new Error("Missing encrypted payload (--payload, --payload-file, or EIGENDARK_PAYLOAD)");
}
