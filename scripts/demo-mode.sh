#!/usr/bin/env bash
#
# Demo helper:
# - Starts an ngrok tunnel for the local gateway (port 4000 by default)
# - Rewrites the compute app .env to point GATEWAY_WEBHOOK_URL at the tunnel
# - Runs scripts/run-e2e.sh to exercise the full flow
# - Restores the original compute .env and stops ngrok on exit
#
# Prereqs: ngrok authenticated, jq, curl, plus everything required by run-e2e.sh.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env"
COMPUTE_ENV="${ROOT_DIR}/off-chain/compute/app/.env"
GATEWAY_PORT=${GATEWAY_PORT:-4000}
NGROK_LOG="${ROOT_DIR}/ngrok-gateway.log"
NGROK_PID=""
COMPUTE_ENV_BACKUP=""

ensure_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Required command '$1' not found on PATH" >&2
    exit 1
  fi
}

cleanup() {
  if [[ -n "$COMPUTE_ENV_BACKUP" && -f "$COMPUTE_ENV_BACKUP" ]]; then
    echo "Restoring compute env..."
    cp "$COMPUTE_ENV_BACKUP" "$COMPUTE_ENV" || true
  fi
  if [[ -n "$NGROK_PID" ]] && ps -p "$NGROK_PID" >/dev/null 2>&1; then
    echo "Stopping ngrok (pid $NGROK_PID)..."
    kill "$NGROK_PID" >/dev/null 2>&1 || true
  fi
}

trap cleanup EXIT

for bin in ngrok jq curl; do
  ensure_cmd "$bin"
done

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing ${ENV_FILE}. Populate it before running demo-mode." >&2
  exit 1
fi

if [[ ! -f "$COMPUTE_ENV" ]]; then
  echo "Missing compute env at ${COMPUTE_ENV}" >&2
  exit 1
fi

echo "Launching ngrok tunnel for http://127.0.0.1:${GATEWAY_PORT} ..."
ngrok http "${GATEWAY_PORT}" --log=stdout >"$NGROK_LOG" 2>&1 &
NGROK_PID=$!

# Wait for ngrok API to expose the tunnel
TUNNEL_URL=""
for i in {1..15}; do
  sleep 1
  if TUNNEL_URL=$(curl -fsS http://127.0.0.1:4040/api/tunnels 2>/dev/null | jq -r '.tunnels[] | select(.proto == "https") | .public_url' | head -n1); then
    if [[ -n "$TUNNEL_URL" && "$TUNNEL_URL" != "null" ]]; then
      break
    fi
  fi
done

if [[ -z "$TUNNEL_URL" || "$TUNNEL_URL" == "null" ]]; then
  echo "Failed to obtain ngrok tunnel URL. See ${NGROK_LOG} for details." >&2
  exit 1
fi

echo "ngrok tunnel ready: ${TUNNEL_URL}"

# Backup and patch compute env
COMPUTE_ENV_BACKUP=$(mktemp)
cp "$COMPUTE_ENV" "$COMPUTE_ENV_BACKUP"

if grep -q '^GATEWAY_WEBHOOK_URL=' "$COMPUTE_ENV"; then
  perl -0pi -e "s|^GATEWAY_WEBHOOK_URL=.*$|GATEWAY_WEBHOOK_URL=${TUNNEL_URL}/settlements|m" "$COMPUTE_ENV"
else
  echo "GATEWAY_WEBHOOK_URL=${TUNNEL_URL}/settlements" >>"$COMPUTE_ENV"
fi

echo "Patched compute env GATEWAY_WEBHOOK_URL -> ${TUNNEL_URL}/settlements"

# Run the existing full E2E script
"${ROOT_DIR}/scripts/run-e2e.sh"

