#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ENV_FILE:-$ROOT_DIR/.env}"
IMAGE_TAG="${IMAGE_TAG:-eigendark/compute:local}"

if [ ! -f "$ENV_FILE" ]; then
  echo "Missing environment file: $ENV_FILE" >&2
  exit 1
fi

if ! command -v eigenx >/dev/null 2>&1; then
  echo "eigenx CLI is not installed. Install it via https://docs.eigenlayer.xyz/eigencompute/get-started/quickstart" >&2
  exit 1
fi

pushd "$ROOT_DIR" >/dev/null

pnpm install --frozen-lockfile
pnpm build

docker buildx build --platform=linux/amd64 -t "$IMAGE_TAG" .

echo "Deploying to EigenCompute via eigenx CLI..."
eigenx app deploy --path "$ROOT_DIR" --env "$ENV_FILE"

echo "Deployment request sent. Use 'eigenx app info' to inspect the instance."

popd >/dev/null
