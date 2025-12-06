# EigenDark CLI

Command-line helper for traders, LPs, and operators interacting with the EigenDark gateway.

## Setup

```bash
cd off-chain/cli
pnpm install
pnpm build
pnpm start -- --help
```

Or run in watch mode:

```bash
pnpm dev -- --help
```

Environment variables (optional):

| Variable | Description |
|----------|-------------|
| `GATEWAY_URL` | Gateway base URL (`http://127.0.0.1:4000`) |
| `COMPUTE_URL` | Compute health URL (`http://127.0.0.1:8080`) |
| `CLIENT_API_KEY` | API key for `/orders` |
| `ADMIN_API_KEY` | Admin key for `/admin/*` + `/metrics` |
| `EIGENDARK_PAYLOAD` | Default encrypted order payload |

## Examples

Check health:

```bash
pnpm start -- health --gateway-url http://localhost:4000
```

Submit an order:

```bash
pnpm start -- orders submit \
  --trader 0xYourTrader \
  --token-in 0xTokenA \
  --token-out 0xTokenB \
  --amount 1 \
  --limit-price 1 \
  --payload-file ./encrypted-order.json
```

Admin stats:

```bash
pnpm start -- gateway stats --gateway-url http://localhost:4000 --admin-key $ADMIN_API_KEY
```


