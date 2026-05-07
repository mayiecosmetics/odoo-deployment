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
DB_NAME="${POSTGRES_DB:-mayie_erp}"
REBUILD=false
[[ "${1:-}" == "--rebuild" ]] && REBUILD=true

COMPOSE="docker compose -f docker-compose.yml -f docker-compose.prod.yml"

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
echo "[1/7] Pulling latest deployment config..."
git pull origin main

# ---------------------------------------------------------------------------
# 2. Clone or update Odoo Enterprise addons
# ---------------------------------------------------------------------------
echo "[2/7] Syncing Odoo Enterprise addons..."
ENTERPRISE_DIR="$PROJECT_DIR/addons/enterprise"

if [ -n "${ODOO_ENTERPRISE_GITHUB_TOKEN:-}" ]; then
    # --- GitHub-token path: clone / update from odoo/enterprise repo ---
    ENTERPRISE_REPO="https://${ODOO_ENTERPRISE_GITHUB_TOKEN}@github.com/odoo/enterprise"

    if [ -d "$ENTERPRISE_DIR/.git" ]; then
        echo "  Updating enterprise addons from GitHub (branch $ODOO_VERSION)..."
        git -C "$ENTERPRISE_DIR" fetch origin
        git -C "$ENTERPRISE_DIR" checkout "$ODOO_VERSION"
        git -C "$ENTERPRISE_DIR" pull origin "$ODOO_VERSION"
    else
        echo "  Cloning enterprise addons from GitHub (branch $ODOO_VERSION)..."
        rm -rf "$ENTERPRISE_DIR"
        git clone \
            --branch "$ODOO_VERSION" \
            --single-branch \
            --depth 1 \
            "$ENTERPRISE_REPO" \
            "$ENTERPRISE_DIR"
    fi
    echo "  Enterprise addons ready (GitHub)."

elif [ -d "$ENTERPRISE_DIR/web_enterprise" ]; then
    # --- Pre-placed path: addons already uploaded (e.g. extracted from .deb) ---
    echo "  Enterprise addons already present (pre-placed) ✓"
    echo "  Skipping GitHub clone — using existing $ENTERPRISE_DIR"

else
    echo "  ⚠  No enterprise addons found."
    echo "     Set ODOO_ENTERPRISE_GITHUB_TOKEN in .env, or"
    echo "     rsync your extracted addons to: $ENTERPRISE_DIR"
    echo "     Running in Community mode."
fi

# ---------------------------------------------------------------------------
# 3. Build Docker image (only if needed or --rebuild)
# ---------------------------------------------------------------------------
echo "[3/7] Building Docker image..."
if $REBUILD; then
    $COMPOSE build --no-cache odoo
else
    $COMPOSE build odoo
fi

# ---------------------------------------------------------------------------
# 4. Start / restart the stack
# ---------------------------------------------------------------------------
echo "[4/7] Starting stack..."
$COMPOSE up -d --remove-orphans

# ---------------------------------------------------------------------------
# 5. Wait for Odoo to be healthy
# ---------------------------------------------------------------------------
echo "[5/7] Waiting for Odoo to be ready..."
MAX_WAIT=120
ELAPSED=0
until $COMPOSE exec -T odoo curl -sf http://localhost:8069/web/health > /dev/null 2>&1; do
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
# 6. Activate Odoo Enterprise (first-time only — installs web_enterprise)
# ---------------------------------------------------------------------------
echo "[6/7] Checking Enterprise activation..."

if [ ! -d "$ENTERPRISE_DIR/web_enterprise" ]; then
    echo "  Enterprise addons not present — running in Community mode."
else
    # Check if web_enterprise is already installed in the DB
    WEB_ENT_STATE=$(
        $COMPOSE exec -T db \
            psql -U "${POSTGRES_USER:-odoo}" -d "$DB_NAME" -tAc \
            "SELECT state FROM ir_module_module WHERE name = 'web_enterprise';" \
            2>/dev/null | tr -d '[:space:]' || true
    )

    if [ "$WEB_ENT_STATE" = "installed" ]; then
        echo "  web_enterprise already installed ✓"
    else
        echo "  Installing web_enterprise module (first-time Enterprise activation)..."
        echo "  This may take 2–5 minutes — Odoo will restart automatically."

        # Stop Odoo; keep DB + MinIO running
        $COMPOSE stop odoo

        # One-off install container — replicates the same ADDONS_PATH + config logic
        # as the main service command so Odoo sees the full addons tree.
        $COMPOSE run --rm --no-deps odoo sh -c '
            ADDONS_PATH="/mnt/extra-addons/custom,/mnt/extra-addons/third_party"
            if [ -n "$(ls -A /mnt/extra-addons/enterprise 2>/dev/null)" ]; then
                ADDONS_PATH="/mnt/extra-addons/enterprise,$ADDONS_PATH"
            fi
            export ADDONS_PATH
            envsubst < /etc/odoo/odoo.conf.template > /tmp/odoo.conf
            odoo -c /tmp/odoo.conf -d '"$DB_NAME"' -i web_enterprise --stop-after-init
        '

        # Restart Odoo service
        $COMPOSE up -d odoo

        # Wait for it to become healthy again
        ELAPSED=0
        until $COMPOSE exec -T odoo curl -sf http://localhost:8069/web/health > /dev/null 2>&1; do
            if [ $ELAPSED -ge $MAX_WAIT ]; then
                echo "  ERROR: Odoo did not recover after Enterprise install."
                echo "  Check logs: docker compose logs -f odoo"
                exit 1
            fi
            sleep 5
            ELAPSED=$((ELAPSED + 5))
            echo "  Waiting... (${ELAPSED}s)"
        done

        echo "  web_enterprise installed ✓"
        echo "  → Open Odoo in your browser and enter your subscription code in the banner."
    fi
fi

# ---------------------------------------------------------------------------
# 7. Enable S3 attachment storage in Odoo DB
# ---------------------------------------------------------------------------
echo "[7/7] Enabling S3 attachment storage..."

$COMPOSE exec -T db psql -U "${POSTGRES_USER:-odoo}" "$DB_NAME" -c "
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
