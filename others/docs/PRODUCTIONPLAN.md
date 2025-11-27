# EigenDark Hook – Production Plan

## 1. Scope & Objectives
- Deliver the confidential trading venue described in `README.md`: encrypted LP reserves, private order execution inside EigenCompute TEEs, on-chain settlement through a Uniswap v4 hook, and institutional governance controls.
- Use EigenCloud/EigenCompute services (Intel TDX TEEs, EigenX CLI workflow, EigenLabs KMS) as documented under `CONTEXT/eigencloud-docs`.
- Maintain user trust by enforcing privacy guarantees (orders/reserves hidden, attestations verified) and publishing auditable settlement data only.

### 1.1 Architecture Charter
- **Core principles**: confidential Uniswap v4 hooks, EigenCompute attestations, trust-minimized settlements, institutional controls (KYB, governance pause, auditable logs).
- **Component boundaries**:
  - `EigenDarkHook`: verifies EigenCompute attestations, mediates settlement, enforces pause/attestor rotation.
  - `EigenDarkVault`: safekeeps LP liquidity, executes deltas from hook, supports governance withdrawals.
  - `EigenCompute enclave`: decrypts orders/reserves, fetches Pyth TWAP, matches orders privately, signs EIP-712 settlements.
  - `Gateway + Client tooling`: receives encrypted orders, forwards to enclave, verifies settlements, publishes to hook, exposes SDK/CLI for traders and LPs.
- **Privacy contract**: no FHE; privacy derives from enclave isolation, encrypted payloads, and limited on-chain disclosures (only deltas + attestation).
- **Data flow alignment**: matches README “Technical Architecture” section—trader → gateway → EigenCompute → hook/vault—with EigenLayer/EigenCloud trust anchors.

### 1.2 Success Metrics (from README §Performance Metrics)
| Metric | Target | Notes |
| --- | --- | --- |
| Order-to-Settlement Time | < 30s | Monitor end-to-end latency; alert if >60s for 3 consecutive orders. |
| Gas Cost per Trade | < 300k gas | Maintain CREATE2 deploy + settlement calldata efficiency. |
| Privacy Level | ≥ 98% | Ensure only signed deltas + hashed order IDs leave the enclave. |
| TEE Attestation Success | 100% | No settlement accepted without valid EigenCompute measurement/signature. |
| TWAP Deviation | < 0.1% | Enclave must enforce oracle staleness + deviation guards. |
| Supported Trade Size | $100K – $100M | Vault + hook must sustain at least $50M test cases before launch. |
| TEE Uptime | ≥ 99.97% | Multiple EigenCompute instances + health routing. |
| Settlement Throughput | ≥ 200 orders/min burst | Gateway retry + enqueue design sized accordingly. |

## 2. Core Assumptions
- Privacy derives from EigenCompute TEEs, not FHE (README makes no FHE promise).
- Governance parameters (fees, limits, timelocks, guardians) follow README tables; changes require DAO consent.
- Oracle inputs come from Pyth TWAP with deviation and staleness guards.
- Enclave deployments follow EigenCompute trust model: Docker images published via EigenX CLI, recorded on-chain, and run inside Intel TDX instances with EigenLabs-operated KMS (until threshold KMS ships).

## 3. Workstreams & Milestones

### A. Architecture & Governance (Week 1)
1. Translate README architecture diagram into a formal spec: component boundaries, encrypted vs public data, attestation flow.
2. Codify governance configuration per README YAML (fees, min/max trade sizes, withdrawal delays, pause guardians, multisig).
3. Document trust/attack model using EigenCompute security + privacy docs, including remediation plans for attestation failure.

### B. On-Chain Contracts (Weeks 2-4)
1. Replace `src/Counter.sol` with EigenDark Hook implementation:
   - Validate TEE settlement proofs (signature + measurement check).
   - Enforce TWAP/limit/liq checks, execute transfers via PoolManager, emit audit events.
2. Implement encrypted dark vault contract:
   - Accept LP deposits (with approvals), store encrypted commitments, manage withdrawal queues, apply governance params.
   - Track settlement receipts from hook and reconcile LP shares.
3. Integrate oracle adapter(s) for Pyth TWAP (staleness, deviation, fallback).
4. Build Foundry test suite covering hook callbacks (before/after swap/liquidity), governance controls, emergency pause.

### C. EigenCompute Enclave Service (Weeks 3-6, overlaps B)
1. Design enclave container per EigenCompute quickstart:
   - Order ingestion (encrypted payloads), reserve decryption, price fetch, limit checks, matching logic, encrypted state updates.
   - Settlement proof signer tied to enclave wallet derived from app ID.
2. Implement attestation + key provisioning flow:
   - Use EigenX CLI to build/push Docker image, deploy to Intel TDX, request keys via KMS after attestation validation.
3. Expose APIs required by hook/gateway (e.g., `/settlement/proof`, health, metrics). Bind to `0.0.0.0`, configure ports in Dockerfile.
4. Instrument logging compatible with EigenCloud verification dashboards (deployment metadata, measurement hash, uptime).

### D. Order Gateway & Client Tooling (Weeks 5-7)
1. Build REST/WebSocket gateway that:
   - Accepts trader requests, encrypts payloads with TEE public key, queues for enclave processing, monitors status.
   - Enforces whitelist/min trade size per governance config.
2. Ship CLI + SDK flows mirroring README examples (`eigendark order create/submit/status/details`, TypeScript SDK sample).
3. Provide LP interactions (approve/deposit/query/withdraw) via CLI scripts + documentation; ensure encrypted data retrieval for LP-only dashboards.

### E. Monitoring, Analytics, Compliance (Weeks 6-8)
1. Implement public dashboard metrics aligned with README (trade counts, obfuscated size ranges, fees, uptime) without leaking reserves/orders.
2. Build private LP dashboards showing decrypted balances/earnings; integrate EigenCompute verification data for attestation transparency.
3. Define incident response + key rotation runbooks leveraging EigenCompute KMS; set SLAs (≤30 s settlement, 99.9% enclave uptime).

### F. Security, Testing, Deployment (Weeks 7-10)
1. Testing:
   - Foundry unit/integration tests for contracts (multi-LP, insufficient liquidity, governance transitions, MEV simulation).
   - Enclave integration tests (order lifecycle, failure paths, price deviations).
   - Cross-component end-to-end tests on Sepolia using EigenCompute deployment.
2. Audits + Bug Bounty:
   - Engage firms listed in README (OpenZeppelin, Trail of Bits, Gauntlet, NCC Group).
   - Launch bounty tiers (Critical $100k, High $50k, etc.) once testnet stable.
3. Deployment Pathfinder:
   - Local/Anvil validation, Sepolia beta with published addresses, gated mainnet beta, then public mainnet launch post-audit + SLO verification.
4. Continuous verification:
   - Monitor EigenCloud verify dashboards; automate alerts for attestation drift or KMS anomalies.
   - Enforce reproducible builds + Docker digest pinning for enclave releases.

## 4. Deliverables Checklist
- ✅ Spec + governance doc
- ✅ EigenDark Hook + dark vault contracts + tests
- ✅ EigenCompute enclave container + CI pipeline
- ✅ Order gateway, CLI, SDK, LP UX flows
- ✅ Monitoring/analytics dashboards + runbooks
- ✅ Security audits, bug bounty, deployment playbooks

## 5. Risks & Mitigations
- **TEE/KMS trust**: rely on EigenCompute roadmap (threshold KMS, public attestation); maintain fallback pause/compliance procedures.
- **Oracle manipulation**: enforce TWAP windows, staleness checks, and limit orders per README safety mechanisms.
- **Governance misconfiguration**: dual-sign multisig + timelock for parameter changes; integration tests before execution.
- **Settlement bottlenecks**: scale enclave instances via EigenCloud infrastructure; monitor order queue latency and provision extra TEEs.

## 6. Next Steps
1. Approve architecture/governance spec.
2. Kick off contract implementation while setting up EigenX CLI pipeline.
3. Schedule external audits and align legal/compliance review with institutional partners.

