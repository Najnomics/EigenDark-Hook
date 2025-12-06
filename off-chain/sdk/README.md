# EigenDark TypeScript SDK

Lightweight client for interacting with the EigenDark gateway (orders, settlements, admin ops).

## Installation

```bash
pnpm install @eigendark/sdk
```

## Usage

```ts
import { EigenDarkClient } from "@eigendark/sdk";

const client = new EigenDarkClient({
  gatewayUrl: process.env.GATEWAY_URL ?? "http://127.0.0.1:4000",
  computeUrl: process.env.COMPUTE_URL ?? "http://127.0.0.1:8080",
  clientApiKey: process.env.CLIENT_API_KEY,
  adminApiKey: process.env.ADMIN_API_KEY,
});

async function run() {
  const health = await client.health();
  console.log("Gateway health", health.gateway);

  const order = await client.submitOrder({
    trader: "0x4b992F2Fbf714C0fCBb23baC5130Ace48CaD00cd",
    tokenIn: "0xC0936f7E87607955C617F6491CCe1Eb1bebc1FD3",
    tokenOut: "0xD384d3f622a2949219265E4467d3a8221e9f639C",
    amount: "1",
    limitPrice: "1",
    payload: process.env.EIGENDARK_PAYLOAD!,
  });
  console.log("Submitted order", order);
}

run().catch(console.error);
```

### API Surface

| Method | Description |
|--------|-------------|
| `health()` | Returns `{ gateway, compute? }` heartbeat info. |
| `submitOrder(order)` | Posts encrypted order to gateway. |
| `getSettlement(orderId)` | Fetches settlement details (if available). |
| `adminStats()` | Returns uptime/submitter status (admin key required). |
| `listPending(limit?)` | Lists pending settlements (admin key). |
| `retrySettlements()` | Triggers retry worker once (admin key). |
| `metrics()` | Returns Prometheus metrics text (admin key). |

### Development

```bash
pnpm install
pnpm build
```

