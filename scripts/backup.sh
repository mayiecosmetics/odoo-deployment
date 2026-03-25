#!/usr/bin/env bash
# =============================================================================
# Odoo Backup Script — Mayie Cosmetics
# =============================================================================
# Creates a compressed backup of:
#   1. PostgreSQL database (pg_dump)
#   2. Odoo data directory (/var/lib/odoo — filestore, sessions, etc.)
#
# Usage:
#   ./scripts/backup.sh
#   ./scripts/backup.sh my_database_name
#
# Backups are stored in ./backups/ with timestamps.
# Old backups beyond BACKUP_RETENTION_DAYS are automatically cleaned up.
# =============================================================================

set -euo pipefail

# --- Configuration ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
source "$PROJECT_DIR/.env" 2>/dev/null || true

DB_NAME="${1:-${POSTGRES_DB:-postgres}}"
DB_USER="${POSTGRES_USER:-odoo}"
DB_CONTAINER=$(docker compose -f "$PROJECT_DIR/docker-compose.yml" ps -q db 2>/dev/null || echo "mayie-odoo-db")
BACKUP_DIR="$PROJECT_DIR/backups"
RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="backup_${DB_NAME}_${TIMESTAMP}"

# --- Create backup directory ---
mkdir -p "$BACKUP_DIR"

echo "=== Odoo Backup — $(date) ==="
echo "Database: $DB_NAME"
echo "Target:   $BACKUP_DIR/$BACKUP_NAME.tar.gz"

# --- Dump database ---
echo "[1/3] Dumping PostgreSQL database..."
docker exec "$DB_CONTAINER" pg_dump -U "$DB_USER" "$DB_NAME" \
    > "$BACKUP_DIR/${BACKUP_NAME}.sql"

# --- Copy Odoo data directory ---
echo "[2/3] Backing up Odoo data directory..."
TEMP_DIR=$(mktemp -d)
if [ -d "$PROJECT_DIR/volumes/odoo" ]; then
    cp -r "$PROJECT_DIR/volumes/odoo" "$TEMP_DIR/odoo-data"
else
    echo "Warning: No volumes/odoo directory found, skipping data backup."
    mkdir -p "$TEMP_DIR/odoo-data"
fi
cp "$BACKUP_DIR/${BACKUP_NAME}.sql" "$TEMP_DIR/"

# --- Compress ---
echo "[3/3] Compressing backup..."
tar -czf "$BACKUP_DIR/${BACKUP_NAME}.tar.gz" -C "$TEMP_DIR" .

# --- Cleanup ---
rm -rf "$TEMP_DIR"
rm -f "$BACKUP_DIR/${BACKUP_NAME}.sql"

# --- Remove old backups ---
if [ "$RETENTION_DAYS" -gt 0 ]; then
    echo "Cleaning up backups older than $RETENTION_DAYS days..."
    find "$BACKUP_DIR" -name "backup_*.tar.gz" -mtime +"$RETENTION_DAYS" -delete
fi

echo "=== Backup complete: $BACKUP_DIR/${BACKUP_NAME}.tar.gz ==="
echo "Size: $(du -h "$BACKUP_DIR/${BACKUP_NAME}.tar.gz" | cut -f1)"
