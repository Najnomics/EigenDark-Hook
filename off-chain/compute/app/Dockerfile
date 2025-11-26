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

COPY --from=base /app/dist ./dist
COPY --from=base /app/node_modules ./node_modules
COPY package.json package.json

EXPOSE 8080
CMD ["node", "dist/server.js"]

