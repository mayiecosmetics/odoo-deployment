#!/usr/bin/env bash
# =============================================================================
# Upload pre-extracted Enterprise addons to the Hetzner server
# =============================================================================
# Use this when you have the Enterprise addons locally (e.g. extracted from
# the official .deb package) and want to deploy them without a GitHub token.
#
# Usage:
#   ./scripts/upload-enterprise-addons.sh <user@server-ip>
#
# Example:
#   ./scripts/upload-enterprise-addons.sh root@1.2.3.4
#
# The script rsyncs addons/enterprise/ to the matching path on the server.
# Run this ONCE from your local machine before the first deploy.sh run.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ENTERPRISE_LOCAL="$PROJECT_DIR/addons/enterprise"

if [ -z "${1:-}" ]; then
    echo "Usage: $0 <user@server-ip>"
    echo "  e.g. $0 root@1.2.3.4"
    exit 1
fi

SERVER="$1"
REMOTE_DIR="/opt/odoo-deployment/addons/enterprise"

if [ ! -d "$ENTERPRISE_LOCAL/web_enterprise" ]; then
    echo "ERROR: $ENTERPRISE_LOCAL/web_enterprise not found."
    echo "  Extract addons first:"
    echo "    mkdir -p addons/enterprise"
    echo "    dpkg-deb -x odoo_19.0+e.*_all.deb /tmp/odoo_deb/"
    echo "    cp -r /tmp/odoo_deb/usr/lib/python3/dist-packages/addons/. addons/enterprise/"
    exit 1
fi

MODULE_COUNT=$(ls -1 "$ENTERPRISE_LOCAL" | wc -l | tr -d ' ')
echo "=========================================="
echo " Upload Odoo Enterprise Addons"
echo " Source : $ENTERPRISE_LOCAL"
echo " Target : $SERVER:$REMOTE_DIR"
echo " Modules: $MODULE_COUNT"
echo "=========================================="
echo ""
echo "Starting rsync... (first run may take a few minutes)"
echo ""

rsync -avz --progress --delete \
    "$ENTERPRISE_LOCAL/" \
    "$SERVER:$REMOTE_DIR/"

echo ""
echo "✓ Enterprise addons uploaded to $SERVER:$REMOTE_DIR"
echo ""
echo "Next step — run deploy.sh on the server:"
echo "  ssh $SERVER 'cd /opt/odoo-deployment && ./scripts/deploy.sh'"
