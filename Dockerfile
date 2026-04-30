# syntax=docker/dockerfile:1

# ── Stage 1: Install all deps ────────────────────────────────────────────────
FROM node:24-slim AS deps
WORKDIR /app

COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY packages/ ./packages/
COPY apps/daemon/ ./apps/daemon/
COPY apps/web/ ./apps/web/

RUN npm install -g pnpm@10.33.2 && \
    pnpm install --frozen-lockfile --ignore-scripts

# ── Stage 2: Build all workspace packages first ───────────────────────────────
FROM node:24-slim AS builder
WORKDIR /app

COPY --from=deps /app/node_modules ./node_modules
COPY --from=deps /app/packages ./packages
COPY --from=deps /app/apps ./apps
COPY --from=deps /app/skills ./skills
COPY --from=deps /app/design-systems ./design-systems
COPY --from=deps /app/assets ./assets
COPY --from=deps /app/templates ./templates
COPY --from=deps /app/deploy ./deploy

ENV NODE_ENV=production
ENV OD_WEB_OUTPUT_MODE=server
ENV OD_PORT=7456

# Build workspace packages first (needed by daemon/web)
RUN pnpm --filter "@open-design/sidecar-proto" --filter "@open-design/platform" --filter "@open-design/sidecar" build

# Build daemon (includes sidecar)
RUN pnpm --filter "@open-design/contracts" build && \
    pnpm --filter "@open-design/daemon" build

# Build web
RUN pnpm --filter "@open-design/web" build

# ── Stage 3: runtime ────────────────────────────────────────────────────────
FROM node:24-slim AS runtime

ENV NODE_ENV=production
ENV OD_WEB_OUTPUT_MODE=server
ENV OD_PORT=7456

WORKDIR /app

RUN npm install -g pnpm@10.33.2 && \
    pnpm install --frozen-lockfile --ignore-scripts --filter "@open-design/daemon"

COPY --from=builder /app/apps/daemon/dist ./apps/daemon/dist
COPY --from=builder /app/apps/web/.next ./apps/web/.next
COPY --from=builder /app/apps/web/public ./apps/web/public
COPY --from=builder /app/apps/web/next.config.ts ./apps/web/next.config.ts
COPY --from=builder /app/apps/web/package.json ./apps/web/package.json
COPY --from=builder /app/packages ./packages
COPY --from=builder /app/node_modules ./node_modules

COPY --from=builder /app/skills ./skills
COPY --from=builder /app/design-systems ./design-systems
COPY --from=builder /app/assets ./assets
COPY --from=builder /app/templates ./templates
COPY --from=builder /app/deploy ./deploy

EXPOSE 7456

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD curl -sf http://localhost:7456/api/health || exit 1

CMD ["node", "apps/daemon/dist/cli.js"]