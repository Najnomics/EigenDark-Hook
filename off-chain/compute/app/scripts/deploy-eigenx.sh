#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ENV_FILE:-$ROOT_DIR/.env}"

if [ ! -f "$ENV_FILE" ]; then
  echo "Missing environment file: $ENV_FILE" >&2
  exit 1
fi

if ! command -v eigenx >/dev/null 2>&1; then
  echo "eigenx CLI is not installed. Install it via https://docs.eigenlayer.xyz/eigencompute/get-started/quickstart" >&2
  exit 1
fi

pushd "$ROOT_DIR" >/dev/null

echo "Building application..."
pnpm install --frozen-lockfile
pnpm build

echo ""
echo "Deploying to EigenCompute via eigenx CLI..."
echo "Using env file: $ENV_FILE"
echo ""

# EigenX will automatically build and push the Docker image
# It uses the Dockerfile in the current directory
eigenx app deploy --env-file "$ENV_FILE"

echo ""
echo "✅ Deployment request sent!"
echo ""
echo "Next steps:"
echo "  - Check status: eigenx app info"
echo "  - View logs: eigenx app logs"
echo "  - List apps: eigenx app list"

popd >/dev/null
