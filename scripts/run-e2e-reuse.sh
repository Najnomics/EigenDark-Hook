#!/usr/bin/env bash

# End-to-end runner that reuses already-deployed tokens/pool from README
# - Starts compute (Docker) on 8080 and gateway on 4000
# - Reuses existing EDT0/EDT1 contracts (defaults from README, override via env)
# - Mints a small balance to the trader and approves the vault (cheap gas)
# - Submits a confidential order through the gateway and waits for settlement
#
# Prereqs: forge/cast, jq, pnpm, docker, curl; root .env populated

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing ${ENV_FILE}. Populate RPC_URL, PRIVATE_KEY, EIGENDARK_HOOK, EIGENDARK_VAULT, CLIENT_API_KEY, ADMIN_API_KEY, COMPUTE_WEBHOOK_KEY." >&2
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
  ADMIN_API_KEY
  COMPUTE_WEBHOOK_KEY
)

for var in "${REQUIRED_VARS[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    echo "Environment variable ${var} must be set in ${ENV_FILE}" >&2
    exit 1
  fi
done

COMPUTE_ENV_FILE="${ROOT_DIR}/off-chain/compute/app/.env"
if [[ ! -f "$COMPUTE_ENV_FILE" ]]; then
  echo "Missing compute env file at ${COMPUTE_ENV_FILE}" >&2
  exit 1
fi

ensure_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Required command '$1' not found on PATH" >&2
    exit 1
  fi
}

for bin in pnpm forge cast jq docker curl; do
  ensure_cmd "$bin"
done

if ! docker info >/dev/null 2>&1; then
  echo "Docker is not running. Please start Docker Desktop." >&2
  exit 1
fi

kill_port() {
  local port=$1
  if lsof -ti tcp:"$port" >/dev/null 2>&1; then
    lsof -ti tcp:"$port" | xargs -r kill -9 >/dev/null 2>&1
  fi
}

wait_for_http() {
  local url=$1
  local label=$2
  local attempts=${3:-30}
  local delay=${4:-2}

  for ((i = 1; i <= attempts; i++)); do
    if curl -fsS "$url" >/dev/null 2>&1; then
      return 0
    fi
    sleep "$delay"
  done
  echo "Timed out waiting for ${label}" >&2
  return 1
}

cleanup() {
  if [[ -n "${GATEWAY_PID:-}" ]] && ps -p "$GATEWAY_PID" >/dev/null 2>&1; then
    kill "$GATEWAY_PID" 2>/dev/null || true
  fi
  docker rm -f eigendark-compute-local >/dev/null 2>&1 || true
}

trap cleanup EXIT

COMPUTE_PORT=${COMPUTE_PORT:-8080}
GATEWAY_PORT=${GATEWAY_PORT:-4000}
GAS_PRICE=${GAS_PRICE:-1gwei}

# Default tokens from README (override with TOKEN0_ADDR/TOKEN1_ADDR env if desired)
TOKEN0_ADDR=${TOKEN0_ADDR:-0xC0936f7E87607955C617F6491CCe1Eb1bebc1FD3} # EDT0
TOKEN1_ADDR=${TOKEN1_ADDR:-0xD384d3f622a2949219265E4467d3a8221e9f639C} # EDT1

kill_port "$COMPUTE_PORT"
kill_port "$GATEWAY_PORT"

docker rm -f eigendark-compute-local >/dev/null 2>&1 || true

(cd "${ROOT_DIR}/off-chain/compute/app" && pnpm install --frozen-lockfile >/dev/null 2>&1 && pnpm build >/dev/null 2>&1 && docker build -q -t eigendark-compute-local . >/dev/null 2>&1) || {
  echo "Failed to build compute Docker image. Is Docker running?" >&2
  exit 1
}

docker run -d --name eigendark-compute-local \
  --env-file "$COMPUTE_ENV_FILE" \
  -p "${COMPUTE_PORT}:8080" \
  eigendark-compute-local >/dev/null 2>&1 || {
  echo "Failed to start compute container. Is Docker running?" >&2
  exit 1
}

wait_for_http "http://127.0.0.1:${COMPUTE_PORT}/health" "compute app" >/dev/null 2>&1 || {
  echo "Compute app failed to start" >&2
  exit 1
}

cd "${ROOT_DIR}/off-chain/gateway"
if ! pnpm install --frozen-lockfile >/dev/null 2>&1; then
  echo "Gateway install failed" >&2
  exit 1
fi
if ! pnpm build >/dev/null 2>&1; then
  echo "Gateway build failed" >&2
  exit 1
fi
pnpm start > gateway.log 2>&1 &
GATEWAY_PID=$!
cd "${ROOT_DIR}"
if ! wait_for_http "http://127.0.0.1:${GATEWAY_PORT}/health" "gateway" >/dev/null 2>&1; then
  echo "Gateway failed to start - check gateway.log" >&2
  if [[ -f "${ROOT_DIR}/off-chain/gateway/gateway.log" ]]; then
    tail -20 "${ROOT_DIR}/off-chain/gateway/gateway.log" >&2
  fi
  exit 1
fi

DEPLOYER_ADDR=$(cast wallet address --private-key "$PRIVATE_KEY")

MINT_AMOUNT=$(cast --to-wei 5 ether)
cast send "$TOKEN0_ADDR" "mint(address,uint256)" "$DEPLOYER_ADDR" "$MINT_AMOUNT" --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY" --legacy --gas-price "$GAS_PRICE" >/dev/null 2>&1
cast send "$TOKEN1_ADDR" "mint(address,uint256)" "$DEPLOYER_ADDR" "$MINT_AMOUNT" --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY" --legacy --gas-price "$GAS_PRICE" >/dev/null 2>&1

MAX_UINT="0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
cast send "$TOKEN0_ADDR" "approve(address,uint256)" "$EIGENDARK_VAULT" "$MAX_UINT" --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY" --legacy --gas-price "$GAS_PRICE" >/dev/null 2>&1
cast send "$TOKEN1_ADDR" "approve(address,uint256)" "$EIGENDARK_VAULT" "$MAX_UINT" --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY" --legacy --gas-price "$GAS_PRICE" >/dev/null 2>&1

echo "Submitting confidential order..."
ORDER_RESPONSE=$(curl -fsSL -X POST "http://127.0.0.1:${GATEWAY_PORT}/orders" \
  -H "Content-Type: application/json" \
  -H "x-api-key: ${CLIENT_API_KEY}" \
  -d "{
    \"trader\": \"${DEPLOYER_ADDR}\",
    \"tokenIn\": \"${TOKEN0_ADDR}\",
    \"tokenOut\": \"${TOKEN1_ADDR}\",
    \"amount\": \"1\",
    \"limitPrice\": \"1\",
    \"payload\": \"encrypted_order_data_here\"
  }" 2>/dev/null)

ORDER_ID=$(echo "$ORDER_RESPONSE" | jq -r '.orderId')
if [[ -z "$ORDER_ID" || "$ORDER_ID" == "null" ]]; then
  echo "Order submission failed: ${ORDER_RESPONSE}" >&2
  exit 1
fi
echo "Order ID: ${ORDER_ID}"

echo "Waiting for settlement..."
TX_HASH=""
for ((i = 1; i <= 40; i++)); do
  STATUS_JSON=$(curl -fsSL "http://127.0.0.1:${GATEWAY_PORT}/settlements/${ORDER_ID}" 2>/dev/null || true)
  TX_HASH=$(echo "$STATUS_JSON" | jq -r '.txHash // empty')
  if [[ -n "$TX_HASH" ]]; then
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
EigenDark Reuse Flow Report
========================================

Token0: ${TOKEN0_ADDR}
Token1: ${TOKEN1_ADDR}

Order ID: ${ORDER_ID}
Settlement tx: ${TX_HASH}
Link: ${ETHERSCAN_BASE}/tx/${TX_HASH}

========================================

EOF


