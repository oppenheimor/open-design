# syntax=docker/dockerfile:1

# ── Stage 1: dependencies ──────────────────────────────────────────────────
FROM node:24-slim AS deps
WORKDIR /app

COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY packages/ ./packages/
COPY apps/daemon/ ./apps/daemon/
COPY apps/web/ ./apps/web/

# Install pnpm and workspace deps (skip scripts to avoid native binaries)
RUN corepack enable && corepack prepare pnpm@10.33.2 --activate
RUN pnpm install --frozen-lockfile --ignore-scripts

# ── Stage 2: build ──────────────────────────────────────────────────────────
FROM node:24-slim AS builder
WORKDIR /app

COPY --from=deps /app/node_modules ./node_modules
COPY . .

# Build daemon
RUN pnpm --filter @open-design/daemon build

# Build web (SSR mode)
ENV NODE_ENV=production
ENV OD_WEB_OUTPUT_MODE=server
ENV OD_PORT=7456
RUN pnpm --filter @open-design/web build

# ── Stage 3: runtime ───────────────────────────────────────────────────────
FROM node:24-slim AS runtime

ENV NODE_ENV=production
ENV OD_WEB_OUTPUT_MODE=server
ENV OD_PORT=7456

WORKDIR /app

# Install only what the runtime needs
RUN corepack enable && corepack prepare pnpm@10.33.2 --activate
RUN pnpm install --frozen-lockfile --ignore-scripts --filter @open-design/daemon

COPY --from=builder /app/apps/daemon/dist ./apps/daemon/dist
COPY --from=builder /app/apps/web/.next ./apps/web/.next
COPY --from=builder /app/apps/web/public ./apps/web/public
COPY --from=builder /app/apps/web/next.config.ts ./apps/web/next.config.ts
COPY --from=builder /app/apps/web/package.json ./apps/web/package.json
COPY --from=builder /app/packages ./packages
COPY --from=builder /app/node_modules ./node_modules

# Static assets the daemon serves
COPY --from=builder /app/skills ./skills
COPY --from=builder /app/design-systems ./design-systems
COPY --from=builder /app/assets ./assets
COPY --from=builder /app/templates ./templates

# Nginx config (referenced by the deploy SSH script to start the nginx container)
COPY deploy/nginx/nginx.conf /app/deploy/nginx/nginx.conf

EXPOSE 7456

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD curl -sf http://localhost:7456/api/health || exit 1

CMD ["node", "apps/daemon/dist/cli.js"]