#!/usr/bin/env bash
# =============================================================================
# Odoo Enterprise Deployment Script — Hetzner
# =============================================================================
# Run this on your Hetzner server to deploy or update the stack.
#
# First-time usage:
#   1. Clone the repo:  git clone https://github.com/mayiecosmetics/odoo-deployment
#   2. cd odoo-deployment
#   3. cp .env.example .env && nano .env   (fill in all secrets)
#   4. ./scripts/deploy.sh
#
# Subsequent deploys:
#   ./scripts/deploy.sh
#
# To force a full rebuild (e.g. after Dockerfile changes):
#   ./scripts/deploy.sh --rebuild
#
# Requirements on the Hetzner server:
#   - docker, docker compose v2
#   - git
#   - A valid .env file (see .env.example)
#   - ODOO_ENTERPRISE_GITHUB_TOKEN + ODOO_VERSION set in .env
#     if you want Enterprise addons automatically cloned/updated.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

# Load .env so we can read config
source .env 2>/dev/null || { echo "ERROR: .env not found. Copy .env.example and fill in values."; exit 1; }

ODOO_VERSION="${ODOO_VERSION:-19.0}"
REBUILD=false
[[ "${1:-}" == "--rebuild" ]] && REBUILD=true

echo ""
echo "=========================================="
echo " Odoo Enterprise Deploy — $(date)"
echo " Version : $ODOO_VERSION"
echo " Rebuild : $REBUILD"
echo "=========================================="
echo ""

# ---------------------------------------------------------------------------
# 1. Pull latest deployment config from GitHub
# ---------------------------------------------------------------------------
echo "[1/6] Pulling latest deployment config..."
git pull origin main

# ---------------------------------------------------------------------------
# 2. Clone or update Odoo Enterprise addons
# ---------------------------------------------------------------------------
echo "[2/6] Syncing Odoo Enterprise addons..."
ENTERPRISE_DIR="$PROJECT_DIR/addons/enterprise"

if [ -z "${ODOO_ENTERPRISE_GITHUB_TOKEN:-}" ]; then
    echo "  ⚠  ODOO_ENTERPRISE_GITHUB_TOKEN not set — skipping Enterprise addons."
    echo "     Running in Community mode."
else
    ENTERPRISE_REPO="https://${ODOO_ENTERPRISE_GITHUB_TOKEN}@github.com/odoo/enterprise"

    if [ -d "$ENTERPRISE_DIR/.git" ]; then
        echo "  Updating enterprise addons (branch $ODOO_VERSION)..."
        git -C "$ENTERPRISE_DIR" fetch origin
        git -C "$ENTERPRISE_DIR" checkout "$ODOO_VERSION"
        git -C "$ENTERPRISE_DIR" pull origin "$ODOO_VERSION"
    else
        echo "  Cloning enterprise addons (branch $ODOO_VERSION)..."
        rm -rf "$ENTERPRISE_DIR"
        git clone \
            --branch "$ODOO_VERSION" \
            --single-branch \
            --depth 1 \
            "$ENTERPRISE_REPO" \
            "$ENTERPRISE_DIR"
    fi
    echo "  Enterprise addons ready."
fi

# ---------------------------------------------------------------------------
# 3. Build Docker image (only if needed or --rebuild)
# ---------------------------------------------------------------------------
echo "[3/6] Building Docker image..."
if $REBUILD; then
    docker compose -f docker-compose.yml -f docker-compose.prod.yml build --no-cache odoo
else
    docker compose -f docker-compose.yml -f docker-compose.prod.yml build odoo
fi

# ---------------------------------------------------------------------------
# 4. Start / restart the stack
# ---------------------------------------------------------------------------
echo "[4/6] Starting stack..."
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d --remove-orphans

# ---------------------------------------------------------------------------
# 5. Wait for Odoo to be healthy
# ---------------------------------------------------------------------------
echo "[5/6] Waiting for Odoo to be ready..."
MAX_WAIT=120
ELAPSED=0
until docker compose -f docker-compose.yml -f docker-compose.prod.yml \
        exec -T odoo curl -sf http://localhost:8069/web/health > /dev/null 2>&1; do
    if [ $ELAPSED -ge $MAX_WAIT ]; then
        echo "  ERROR: Odoo did not become healthy within ${MAX_WAIT}s."
        echo "  Check logs: docker compose logs -f odoo"
        exit 1
    fi
    sleep 5
    ELAPSED=$((ELAPSED + 5))
    echo "  Waiting... (${ELAPSED}s)"
done
echo "  Odoo is up."

# ---------------------------------------------------------------------------
# 6. Enable S3 attachment storage in Odoo DB
# ---------------------------------------------------------------------------
echo "[6/6] Enabling S3 attachment storage..."
DB_NAME="${POSTGRES_DB:-mayie_erp}"

docker compose exec -T db psql -U "${POSTGRES_USER:-odoo}" "$DB_NAME" -c "
  INSERT INTO ir_config_parameter (key, value)
  VALUES ('ir_attachment.location', 's3')
  ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
" && echo "  ir_attachment.location = s3 ✓" || echo "  (Could not set S3 param — set it manually in Settings > Technical > System Parameters)"

echo ""
echo "=========================================="
echo " Deploy complete!"
echo ""
echo " Odoo          : https://your-domain.com"
echo " MinIO Console : https://minio.your-domain.com"
echo ""
echo " Logs          : docker compose logs -f odoo"
echo "=========================================="
