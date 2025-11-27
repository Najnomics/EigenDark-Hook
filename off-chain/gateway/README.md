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
EIGEN_COMPUTE_URL=http://localhost:8080
COMPUTE_WEBHOOK_KEY=dev-hook
API_KEY=dev
```

## Scripts

- `pnpm dev` – run with nodemon + ts-node in watch mode
- `pnpm build` – emit JS to `dist/`
- `pnpm start` – run compiled server

## Flow

1. Clients `POST /orders` with an encrypted payload + metadata.
2. Gateway validates input and forwards it to the EigenCompute app (`EIGEN_COMPUTE_URL`).
3. The compute service performs private execution and calls back `POST /settlements`
   with a signed settlement + attestation. The gateway currently logs the payload;
   the next step is to verify the signature and push to the on-chain hook.

