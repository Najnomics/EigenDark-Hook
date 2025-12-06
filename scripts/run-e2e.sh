#!/usr/bin/env bash

# Automated end-to-end runner for EigenDark
# - Spins up the compute app Docker container (port 8080)
# - Launches the gateway server (port 4000)
# - Deploys fresh ERC20 test tokens, configures the hook/vault, and funds liquidity
# - Submits a confidential order through the gateway and waits for settlement
#
# Prerequisites:
#   - forge/cast, jq, pnpm, docker, curl available on PATH
#   - Root-level .env populated with:
#       RPC_URL, PRIVATE_KEY, EIGENDARK_HOOK, EIGENDARK_VAULT,
#       CLIENT_API_KEY, ADMIN_API_KEY, COMPUTE_WEBHOOK_KEY, etc.
#   - off-chain/compute/app/.env contains compute-specific secrets (TEE key, etc.)

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing ${ENV_FILE}. Populate it with RPC_URL, PRIVATE_KEY, and gateway secrets." >&2
  exit 1
fi

set -a
source "$ENV_FILE"
set +a

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

kill_port() {
  local port=$1
  if lsof -ti tcp:"$port" >/dev/null 2>&1; then
    echo "Freeing port ${port}"
    lsof -ti tcp:"$port" | xargs -r kill -9
  fi
}

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

cleanup() {
  echo "Cleaning up background services..."
  if [[ -n "${GATEWAY_PID:-}" ]] && ps -p "$GATEWAY_PID" >/dev/null 2>&1; then
    kill "$GATEWAY_PID" 2>/dev/null || true
  fi
  docker rm -f eigendark-compute-local >/dev/null 2>&1 || true
}

trap cleanup EXIT

COMPUTE_PORT=${COMPUTE_PORT:-8080}
GATEWAY_PORT=${GATEWAY_PORT:-4000}

kill_port "$COMPUTE_PORT"
kill_port "$GATEWAY_PORT"

docker rm -f eigendark-compute-local >/dev/null 2>&1 || true

echo "Building EigenDark compute Docker image..."
(cd "${ROOT_DIR}/off-chain/compute/app" && pnpm install --frozen-lockfile && pnpm build && docker build -t eigendark-compute-local .)

echo "Starting EigenDark compute container..."
docker run -d --name eigendark-compute-local \
  --env-file "$COMPUTE_ENV_FILE" \
  -p "${COMPUTE_PORT}:8080" \
  eigendark-compute-local >/dev/null

wait_for_http "http://127.0.0.1:${COMPUTE_PORT}/health" "compute app"

echo "Building and launching gateway..."
(cd "${ROOT_DIR}/off-chain/gateway" && pnpm install --frozen-lockfile && pnpm build && pnpm start > gateway.log 2>&1 &) 
GATEWAY_PID=$!
wait_for_http "http://127.0.0.1:${GATEWAY_PORT}/health" "gateway"

DEPLOYER_ADDR=$(cast wallet address --private-key "$PRIVATE_KEY")
echo "Deployer address: ${DEPLOYER_ADDR}"

deploy_token() {
  local name=$1
  local symbol=$2
  local json
  json=$(forge create \
    --json \
    --rpc-url "$RPC_URL" \
    --private-key "$PRIVATE_KEY" \
    contracts/onchain/src/mocks/TestToken.sol:TestToken \
    --constructor-args "$name" "$symbol")
  echo "$json" | jq -r '.deployedTo'
}

TOKEN0_ADDR=$(deploy_token "EigenDark Token0" "EDT0")
TOKEN1_ADDR=$(deploy_token "EigenDark Token1" "EDT1")
echo "Token0: ${TOKEN0_ADDR}"
echo "Token1: ${TOKEN1_ADDR}"

MINT_AMOUNT=$(cast --to-wei 1000 ether)
DEPOSIT_AMOUNT=$(cast --to-wei 500 ether)

echo "Minting tokens to deployer..."
cast send "$TOKEN0_ADDR" "mint(address,uint256)" "$DEPLOYER_ADDR" "$MINT_AMOUNT" --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY" >/dev/null
cast send "$TOKEN1_ADDR" "mint(address,uint256)" "$DEPLOYER_ADDR" "$MINT_AMOUNT" --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY" >/dev/null

echo "Approving vault for both tokens..."
MAX_UINT="0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
cast send "$TOKEN0_ADDR" "approve(address,uint256)" "$EIGENDARK_VAULT" "$MAX_UINT" --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY" >/dev/null
cast send "$TOKEN1_ADDR" "approve(address,uint256)" "$EIGENDARK_VAULT" "$MAX_UINT" --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY" >/dev/null

echo "Depositing liquidity into EigenDark vault..."
cast send "$EIGENDARK_VAULT" \
  "deposit((address,address,uint24,int24,address),uint256,uint256)" \
  "(${TOKEN0_ADDR},${TOKEN1_ADDR},3000,60,${EIGENDARK_HOOK})" \
  "$DEPOSIT_AMOUNT" \
  "$DEPOSIT_AMOUNT" \
  --rpc-url "$RPC_URL" \
  --private-key "$PRIVATE_KEY" >/dev/null

echo "Configuring hook & pool via forge script..."
POOL_TOKEN0="$TOKEN0_ADDR" POOL_TOKEN1="$TOKEN1_ADDR" \
  forge script contracts/onchain/script/02_ConfigureHook.s.sol:ConfigureHookScript \
  --rpc-url "$RPC_URL" \
  --private-key "$PRIVATE_KEY" \
  --broadcast >/dev/null

echo "Submitting confidential order via gateway..."
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
  }")

ORDER_ID=$(echo "$ORDER_RESPONSE" | jq -r '.orderId')
echo "Gateway accepted order ${ORDER_ID}"

echo "Waiting for settlement & on-chain tx..."
TX_HASH=""
for ((i = 1; i <= 40; i++)); do
  STATUS_JSON=$(curl -fsSL "http://127.0.0.1:${GATEWAY_PORT}/settlements/${ORDER_ID}" || true)
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

echo "EigenDark end-to-end run complete."
echo "  Token0: ${TOKEN0_ADDR}"
echo "  Token1: ${TOKEN1_ADDR}"
echo "  Order ID: ${ORDER_ID}"
echo "  Settlement tx: ${TX_HASH}"


