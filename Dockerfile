# syntax=docker/dockerfile:1

ARG PNPM_VERSION=10.33.2

# ── Stage 1: Install deps ────────────────────────────────────────────────────
FROM node:24-slim AS deps
WORKDIR /app

COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY packages/ ./packages/
COPY apps/ ./apps/
COPY skills/ ./skills/
COPY design-systems/ ./design-systems/
COPY assets/ ./assets/
COPY templates/ ./templates/
COPY deploy/ ./deploy/

RUN npm install -g pnpm@${PNPM_VERSION} \
    && pnpm install --frozen-lockfile --ignore-scripts

# ── Stage 2: Build ──────────────────────────────────────────────────────────
FROM node:24-slim AS builder
WORKDIR /app

COPY --from=deps /app/node_modules ./node_modules
COPY --from=deps /app ./

ENV NODE_ENV=production \
    OD_WEB_OUTPUT_MODE=server \
    OD_PORT=7456 \
    PNPM_VERSION=10.33.2

RUN npm install -g pnpm@${PNPM_VERSION} \
    && pnpm --filter "@open-design/sidecar-proto" build \
    && pnpm --filter "@open-design/platform" build \
    && pnpm --filter "@open-design/sidecar" build \
    && pnpm --filter "@open-design/daemon" build \
    && pnpm --filter "@open-design/web" build

# ── Stage 3: Runtime ─────────────────────────────────────────────────────────
FROM node:24-slim AS runtime

ENV NODE_ENV=production \
    OD_WEB_OUTPUT_MODE=server \
    OD_PORT=7456 \
    PNPM_VERSION=10.33.2

WORKDIR /app

# Install SQLite runtime library needed by better-sqlite3 native addon
RUN apt-get update && apt-get install -y --no-install-recommends libsqlite3-0

COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/packages ./packages
COPY --from=builder /app/apps/daemon/dist ./apps/daemon/dist
COPY --from=builder /app/apps/daemon/package.json ./apps/daemon/package.json
COPY --from=builder /app/apps/web/.next ./apps/web/.next
COPY --from=builder /app/apps/web/public ./apps/web/public
COPY --from=builder /app/apps/web/next.config.ts ./apps/web/next.config.ts
COPY --from=builder /app/apps/web/package.json ./apps/web/package.json
COPY --from=builder /app/skills ./skills
COPY --from=builder /app/design-systems ./design-systems
COPY --from=builder /app/assets ./assets
COPY --from=builder /app/templates ./templates
COPY --from=builder /app/deploy ./deploy
COPY --from=builder /app/pnpm-lock.yaml ./apps/daemon/pnpm-lock.yaml

# Re-install daemon's transitive production deps (express, better-sqlite3, etc.)
# that are missing because pnpm workspace isolation keeps them in package-local node_modules
RUN npm install -g pnpm@${PNPM_VERSION} \
    && pnpm install --no-frozen-lockfile --ignore-scripts --prod -r --filter "@open-design/daemon"

EXPOSE 7456

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD curl -sf http://localhost:7456/api/health || exit 1

CMD ["node", "apps/daemon/dist/cli.js"]