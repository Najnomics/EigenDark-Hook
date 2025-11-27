# syntax=docker/dockerfile:1.6
FROM --platform=linux/amd64 node:18-bullseye-slim AS base
WORKDIR /app

COPY package.json pnpm-lock.yaml* ./
RUN corepack enable && pnpm install --frozen-lockfile

COPY tsconfig.json tsconfig.json
COPY src ./src

RUN pnpm build && pnpm prune --prod

FROM --platform=linux/amd64 node:18-bullseye-slim
WORKDIR /app

ENV NODE_ENV=production
ENV PORT=8080

RUN apt-get update && \
    apt-get install -y --no-install-recommends curl && \
    rm -rf /var/lib/apt/lists/*

COPY --from=base /app/dist ./dist
COPY --from=base /app/node_modules ./node_modules
COPY package.json package.json

RUN addgroup --system eigen && \
    adduser --system --ingroup eigen eigen && \
    chown -R eigen:eigen /app

USER eigen

EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD curl -fsS http://127.0.0.1:${PORT:-8080}/health || exit 1
CMD ["node", "dist/server.js"]

