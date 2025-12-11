#!/usr/bin/env bash

# End-to-end runner using DEPLOYED gateway and compute app (no local Docker)
# - Uses deployed gateway URL (from env or default)
# - Uses deployed compute app (gateway forwards to it)
# - Reuses existing EDT0/EDT1 contracts (defaults from README, override via env)
# - Mints a small balance to the trader and approves the vault (cheap gas)
# - Submits a confidential order through the deployed gateway and waits for settlement
#
# Prereqs: forge/cast, jq, curl; root .env populated
#
# Usage:
#   GATEWAY_URL=https://eigendark-hook-production.up.railway.app ./scripts/run-e2e-deployed.sh
#   # Or set GATEWAY_URL in .env

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing ${ENV_FILE}. Populate RPC_URL, PRIVATE_KEY, EIGENDARK_HOOK, EIGENDARK_VAULT, CLIENT_API_KEY." >&2
  exit 1
fi

set -a
source "$ENV_FILE"
set +a

ETHERSCAN_BASE=${ETHERSCAN_BASE:-https://sepolia.etherscan.io}

REQUIRED_VARS=(
  RPC_URL
  PRIVATE_KEY
  EIGENDARK_HOOK
  EIGENDARK_VAULT
  CLIENT_API_KEY
)

for var in "${REQUIRED_VARS[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    echo "Environment variable ${var} must be set in ${ENV_FILE}" >&2
    exit 1
  fi
done

ensure_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Required command '$1' not found on PATH" >&2
    exit 1
  fi
}

for bin in forge cast jq curl; do
  ensure_cmd "$bin"
done

wait_for_http() {
  local url=$1
  local label=$2
  local attempts=${3:-30}
  local delay=${4:-2}

  echo "Waiting for ${label} at ${url}"
  for ((i = 1; i <= attempts; i++)); do
    if curl -fsS "$url" >/dev/null 2>&1; then
      echo "${label} is ready"
      return 0
    fi
    sleep "$delay"
  done
  echo "Timed out waiting for ${label}" >&2
  return 1
}

GATEWAY_URL=${GATEWAY_URL:-https://eigendark-hook-production.up.railway.app}
GAS_PRICE=${GAS_PRICE:-1gwei}

# Default tokens from README (override with TOKEN0_ADDR/TOKEN1_ADDR env if desired)
TOKEN0_ADDR=${TOKEN0_ADDR:-0xC0936f7E87607955C617F6491CCe1Eb1bebc1FD3} # EDT0
TOKEN1_ADDR=${TOKEN1_ADDR:-0xD384d3f622a2949219265E4467d3a8221e9f639C} # EDT1

echo "Using deployed gateway: ${GATEWAY_URL}"
wait_for_http "${GATEWAY_URL}/health" "deployed gateway"

DEPLOYER_ADDR=$(cast wallet address --private-key "$PRIVATE_KEY")
echo "Trader/LP address: ${DEPLOYER_ADDR}"

MINT_AMOUNT=$(cast --to-wei 5 ether)
echo "Minting small balances to trader (cheap)..."
cast send "$TOKEN0_ADDR" "mint(address,uint256)" "$DEPLOYER_ADDR" "$MINT_AMOUNT" --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY" --legacy --gas-price "$GAS_PRICE" >/dev/null
cast send "$TOKEN1_ADDR" "mint(address,uint256)" "$DEPLOYER_ADDR" "$MINT_AMOUNT" --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY" --legacy --gas-price "$GAS_PRICE" >/dev/null

echo "Approving vault for both tokens..."
MAX_UINT="0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
cast send "$TOKEN0_ADDR" "approve(address,uint256)" "$EIGENDARK_VAULT" "$MAX_UINT" --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY" --legacy --gas-price "$GAS_PRICE" >/dev/null
cast send "$TOKEN1_ADDR" "approve(address,uint256)" "$EIGENDARK_VAULT" "$MAX_UINT" --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY" --legacy --gas-price "$GAS_PRICE" >/dev/null

echo "Submitting confidential order via deployed gateway using existing pool..."
ORDER_RESPONSE=$(curl -fsSL -X POST "${GATEWAY_URL}/orders" \
  -H "Content-Type: application/json" \
  -H "x-api-key: ${CLIENT_API_KEY}" \
  -d "{
    \"trader\": \"${DEPLOYER_ADDR}\",
    \"tokenIn\": \"${TOKEN0_ADDR}\",
    \"tokenOut\": \"${TOKEN1_ADDR}\",
    \"amount\": \"1\",
    \"limitPrice\": \"1\",
    \"payload\": \"encrypted_order_data_here\"
  }")

ORDER_ID=$(echo "$ORDER_RESPONSE" | jq -r '.orderId')
if [[ -z "$ORDER_ID" || "$ORDER_ID" == "null" ]]; then
  echo "Order submission failed: ${ORDER_RESPONSE}" >&2
  exit 1
fi
echo "Gateway accepted order ${ORDER_ID}"

echo "Waiting for settlement & on-chain tx..."
TX_HASH=""
for ((i = 1; i <= 40; i++)); do
  STATUS_JSON=$(curl -fsSL "${GATEWAY_URL}/settlements/${ORDER_ID}" || true)
  TX_HASH=$(echo "$STATUS_JSON" | jq -r '.txHash // empty')
  if [[ -n "$TX_HASH" ]]; then
    echo "Settlement submitted on-chain: ${TX_HASH}"
    break
  fi
  sleep 6
done

if [[ -z "$TX_HASH" ]]; then
  echo "Settlement did not reach on-chain state within timeout" >&2
  exit 1
fi

cat <<EOF

========================================
EigenDark Deployed Services Flow Report
========================================

Using deployed services:
  • Gateway: ${GATEWAY_URL}
  • Compute: (deployed, managed by gateway)

Using existing pool:
  • Token0: ${TOKEN0_ADDR}
  • Token1: ${TOKEN1_ADDR}

Order & Settlement:
  • Order ID: ${ORDER_ID}
  • Settlement tx: ${TX_HASH}
      Link: ${ETHERSCAN_BASE}/tx/${TX_HASH}

Gateway health: ${GATEWAY_URL}/health

========================================

EOF

