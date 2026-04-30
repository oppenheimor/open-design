#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────
# Open Design — initial server setup script
# Run once on the target machine to:
#   1. Pull the Docker image from GHCR
#   2. Start the container with volume mount
#   3. Start Nginx as a separate container
# ─────────────────────────────────────────────────────────────────────────
set -euo pipefail

SERVER_IP="${SERVER_IP:-43.137.38.67}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
IMAGE="ghcr.io/nexu-io/open-design:${IMAGE_TAG}"
CONTAINER_NAME="open-design"

echo "[setup] Server IP : $SERVER_IP"
echo "[setup] Image     : $IMAGE"

# ── Docker image ──────────────────────────────────────────────────────────────
echo "[setup] Pulling Docker image…"
docker pull "$IMAGE"

if docker ps --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
  echo "[setup] Removing old container…"
  docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
fi

echo "[setup] Starting open-design container…"
docker run -d \
  --name "$CONTAINER_NAME" \
  --restart unless-stopped \
  -p 7456:7456 \
  -v od-data:/app/.od \
  -e NODE_ENV=production \
  -e OD_HOST=0.0.0.0 \
  -e OD_PORT=7456 \
  "$IMAGE"

# ── Health check ────────────────────────────────────────────────────────────────
echo "[setup] Waiting for daemon to be healthy…"
for i in $(seq 1 30); do
  if curl -sf http://127.0.0.1:7456/api/health >/dev/null 2>&1; then
    echo "[setup] ✓ Daemon is healthy"
    break
  fi
  echo "[setup] attempt $i/30…"
  sleep 2
done

# ── Nginx ──────────────────────────────────────────────────────────────────────
echo "[setup] Starting Nginx reverse-proxy container…"
NGINX_CONF="$(pwd)/deploy/nginx/nginx.conf"
if [[ ! -f "$NGINX_CONF" ]]; then
  echo "[setup] ERROR: nginx.conf not found at $NGINX_CONF"
  exit 1
fi

docker rm -f nginx 2>/dev/null || true
docker run -d \
  --name nginx \
  --restart unless-stopped \
  -p 80:80 \
  -p 443:443 \
  -v "$NGINX_CONF:/etc/nginx/nginx.conf:ro" \
  nginx:alpine

echo ""
echo "══════════════════════════════════════════════════"
echo "✓ Open Design deployed at http://$SERVER_IP"
echo ""
echo "  Health check: http://127.0.0.1:7456/api/health"
echo "  Container logs: docker logs -f $CONTAINER_NAME"
echo "══════════════════════════════════════════════════"
