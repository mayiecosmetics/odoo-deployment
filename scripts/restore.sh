#!/usr/bin/env bash
# =============================================================================
# Odoo Restore Script — Mayie Cosmetics
# =============================================================================
# Restores a backup created by backup.sh:
#   1. Drops and recreates the database
#   2. Restores PostgreSQL dump
#   3. Restores filestore
#
# Usage:
#   ./scripts/restore.sh ./backups/backup_postgres_20260325_120000.tar.gz
#   ./scripts/restore.sh ./backups/backup_postgres_20260325_120000.tar.gz my_database_name
#
# WARNING: This will DROP the existing database. Make sure you have a backup.
# =============================================================================

set -euo pipefail

# --- Validate input ---
if [ $# -lt 1 ]; then
    echo "Usage: $0 <backup_file.tar.gz> [database_name]"
    exit 1
fi

BACKUP_FILE="$1"
if [ ! -f "$BACKUP_FILE" ]; then
    echo "Error: Backup file not found: $BACKUP_FILE"
    exit 1
fi

# --- Configuration ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
source "$PROJECT_DIR/.env" 2>/dev/null || true

DB_NAME="${2:-${POSTGRES_DB:-postgres}}"
DB_CONTAINER="mayie-odoo-db"
ODOO_CONTAINER="mayie-odoo-app"

echo "=== Odoo Restore — $(date) ==="
echo "Backup:   $BACKUP_FILE"
echo "Database: $DB_NAME"
echo ""
echo "WARNING: This will DROP the database '$DB_NAME' and replace it."
read -p "Continue? (y/N) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

# --- Stop Odoo ---
echo "[1/5] Stopping Odoo..."
docker stop "$ODOO_CONTAINER" 2>/dev/null || true

# --- Extract backup ---
echo "[2/5] Extracting backup..."
TEMP_DIR=$(mktemp -d)
tar -xzf "$BACKUP_FILE" -C "$TEMP_DIR"

# --- Find SQL file ---
SQL_FILE=$(find "$TEMP_DIR" -name "*.sql" -type f | head -1)
if [ -z "$SQL_FILE" ]; then
    echo "Error: No SQL dump found in backup archive."
    rm -rf "$TEMP_DIR"
    exit 1
fi

# --- Drop and recreate database ---
echo "[3/5] Recreating database '$DB_NAME'..."
docker exec "$DB_CONTAINER" psql -U "${POSTGRES_USER:-odoo}" -c \
    "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$DB_NAME' AND pid <> pg_backend_pid();" postgres 2>/dev/null || true
docker exec "$DB_CONTAINER" dropdb -U "${POSTGRES_USER:-odoo}" --if-exists "$DB_NAME"
docker exec "$DB_CONTAINER" createdb -U "${POSTGRES_USER:-odoo}" "$DB_NAME"

# --- Restore database ---
echo "[4/5] Restoring database..."
docker exec -i "$DB_CONTAINER" psql -U "${POSTGRES_USER:-odoo}" "$DB_NAME" < "$SQL_FILE"

# --- Restore filestore ---
echo "[5/5] Restoring filestore..."
if [ -d "$TEMP_DIR/filestore" ]; then
    rm -rf "$PROJECT_DIR/volumes/filestore"
    cp -r "$TEMP_DIR/filestore" "$PROJECT_DIR/volumes/filestore"
    echo "Filestore restored."
else
    echo "No filestore in backup, skipping."
fi

# --- Cleanup ---
rm -rf "$TEMP_DIR"

# --- Restart Odoo ---
echo "Starting Odoo..."
docker start "$ODOO_CONTAINER"

echo "=== Restore complete ==="
echo "Odoo is starting up. Check logs with: docker logs -f $ODOO_CONTAINER"
