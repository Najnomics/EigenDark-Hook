# EigenDark Gateway (Off-chain)

Order submission service that:
- Accepts encrypted trade payloads from institutional clients
- Performs schema validation and authentication (to be implemented)
- Routes orders to the EigenCompute enclave queue for private execution

## Getting Started

```bash
cd off-chain/gateway
pnpm install
pnpm dev
```

Environment variables (`.env`):

```
PORT=4000
CHAIN_ID=11155111
HOOK_ADDRESS=0xYourHookAddress
ATTESTATION_MEASUREMENT=0xdeadbeefcafefeed
HOOK_RPC_URL=https://sepolia.infura.io/v3/xxx
HOOK_SUBMITTER_KEY=0xabc123
EIGEN_COMPUTE_URL=http://localhost:8080
COMPUTE_WEBHOOK_KEY=dev-hook
API_KEY=dev
GATEWAY_DATA_DIR=./data
SETTLEMENT_RETRY_MS=30000
CLIENT_API_KEY=dev-client
```

## Scripts

- `pnpm dev` – run with nodemon + ts-node in watch mode
- `pnpm build` – emit JS to `dist/`
- `pnpm start` – run compiled server

## Flow

1. Clients `POST /orders` with an encrypted payload + metadata, including the `x-api-key`
   header matching `CLIENT_API_KEY` when configured.
2. Gateway validates input and forwards it to the EigenCompute app (`EIGEN_COMPUTE_URL`).
3. The compute service performs private execution and calls back `POST /settlements`
   with a signed settlement + attestation. The gateway verifies the EIP-712 signature,
   persists the settlement to disk (`GATEWAY_DATA_DIR`), and (if a submitter key + RPC
   are configured) relays it to `EigenDarkHook.registerSettlement`.
4. A background worker replays any persisted settlements every `SETTLEMENT_RETRY_MS`
   milliseconds, ensuring attestations survive restarts and temporary RPC outages.

