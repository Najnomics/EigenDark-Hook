# EigenDark EigenCompute App

This package is the reference Trusted Execution Environment (TEE) service that receives
encrypted orders from the `off-chain/gateway`, runs private matching logic inside
EigenCompute, and produces signed settlement attestations that the on-chain
`EigenDarkHook` + `EigenDarkVault` can verify.

> **No FHE**: This service relies on EigenCompute’s hardware-backed isolation
> (Intel TDX/AMD SEV). All encryption/decryption occurs inside the enclave, but
> the business logic is regular TypeScript/Node.js.

## Project layout

- `src/server.ts` – Express API exposed inside the TEE (health, `/orders`, `/orders/:id`)
- `src/attestation.ts` – EIP‑712 signing utilities for the on-chain `EigenDarkHook`
- `src/settlementQueue.ts` – in-memory queue that simulates asynchronous enclave execution
- `Dockerfile` – OCI image compatible with `eigenx app deploy`
- `env.example` – required runtime environment variables

## Prerequisites

- Node.js 18+ / PNPM 8+
- [EigenX CLI](https://docs.eigenlayer.xyz/eigencompute/get-started/quickstart/)

```bash
curl -fsSL https://eigenx-scripts.s3.us-east-1.amazonaws.com/install-eigenx.sh | bash
```

## Local development

```bash
cd off-chain/compute/app
cp env.example .env        # populate with your hook/vault addresses + attestor key
pnpm install
pnpm dev                   # runs ts-node with nodemon on http://localhost:8080
```

### Environment variables

| Name | Description |
| --- | --- |
| `HOOK_ADDRESS`, `VAULT_ADDRESS` | On-chain contracts this enclave settles against |
| `ATTESTOR_PRIVATE_KEY` | ECDSA key that signs EIP‑712 settlements |
| `ATTESTATION_MEASUREMENT` | EigenCompute measurement hash surfaced on-chain |
| `GATEWAY_WEBHOOK_URL` | Where to POST generated settlements |
| `GATEWAY_API_KEY` | Optional `x-api-key` header for webhook authentication |
| `ORDER_API_KEY` | Optional `x-api-key` clients must present to call `/orders` |
| `MAX_PENDING_ORDERS` | Back-pressure limit before returning `503` |
| `GATEWAY_TIMEOUT_MS` | HTTP timeout when notifying the public gateway |
| `LOG_LEVEL` | `pino` log level (`info`, `debug`, etc.) |

The service exposes:

- `GET /health` – readiness probe + current measurement + current queue depth
- `POST /orders` – ingest encrypted order payloads (`x-api-key` protected when `ORDER_API_KEY` is set)
- `GET /orders/:orderId` – inspect queue status
- `GET /metrics` – JSON summary of queue status (`queued`, `processing`, `settled`, `failed`)

When a request arrives the mock engine:

1. Marks the order as `processing`
2. Simulates pricing/matching (replace with real enclave business logic)
3. Builds a `Settlement` payload
4. Signs it with the attestor key (EIP‑712, `EigenDarkSettlement` domain)
5. Emits a webhook to `GATEWAY_WEBHOOK_URL` (with optional `GATEWAY_API_KEY`) so
   the public gateway can relay the settlement to on-chain contracts

## Container build (for EigenCompute)

```bash
pnpm build
docker build -t eigendark/compute-app .
```

The Docker image listens on `$PORT` (default 8080) and binds to `0.0.0.0` to
comply with EigenCompute networking rules.

## Deploying with EigenX

1. `eigenx app create eigendark-compute node`
2. Copy this source tree into the generated project (or point `Dockerfile` to the
   container produced above)
3. `eigenx app deploy --env .env`
4. Note the returned `app_id`, `public_key`, and `measurement` – these must be
   mirrored into the on-chain `EigenDarkHook` config and the gateway `.env`

## Next steps

- Replace the mock settlement logic with real TWAP/oracle lookups
- Connect to an actual encrypted order inbox (S3, Kafka, or EigenX message queue)
- Stream attestation metrics to EigenCloud’s verify dashboard for ops/monitoring

