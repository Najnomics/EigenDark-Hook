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
EIGEN_TEE_URL=https://example-enclave
API_KEY=dev
```

## Scripts

- `pnpm dev` – run with nodemon + ts-node in watch mode
- `pnpm build` – emit JS to `dist/`
- `pnpm start` – run compiled server

