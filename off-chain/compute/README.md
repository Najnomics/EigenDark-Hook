# EigenDark Off-Chain Compute Stack

```
off-chain/compute/
 └── app/        # EigenCompute enclave service (Node.js/TypeScript)
```

## Bootstrap via EigenX CLI

1. Install EigenX CLI (see EigenLayer docs).
2. `eigenx app create eigendark-compute node`
3. Copy the contents of `off-chain/compute/app` over the generated project or
   point the EigenX `Dockerfile` to this directory.
4. Populate `.env` (see `env.example`) with the hook/vault addresses that exist
   on-chain plus the attestor private key used for signing settlements.
5. `pnpm install && pnpm build`
6. `eigenx app deploy --env .env`

The deployed app exposes `POST /orders` and `GET /orders/:id` inside the TEE.
It signs settlements using the same EIP‑712 domain that the on-chain
`EigenDarkHook` expects. The `GATEWAY_WEBHOOK_URL` is used to push signed
settlements back to the public gateway so they can be relayed on-chain.

