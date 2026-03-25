# Odoo Deployment — Mayie Cosmetics

Infrastructure repository for the Mayie Cosmetics Odoo ERP deployment.

## Overview

This repository contains everything needed to deploy and manage the Odoo instance:

- Docker Compose configuration
- Odoo server configuration
- Backup and restore scripts
- Nginx reverse proxy configuration (reference)
- Environment variables

## Repository Structure

```
odoo-deployment/
├── docker-compose.yml          # Main Docker orchestration
├── docker-compose.override.yml # Local development overrides
├── .env.example                # Environment variable template
├── config/
│   └── odoo.conf               # Odoo server configuration
├── nginx/
│   └── odoo.conf               # Nginx reverse proxy config (reference)
├── scripts/
│   ├── backup.sh               # Database + data directory backup
│   └── restore.sh              # Restore from backup
├── volumes/                    # Docker volumes (git-ignored)
│   ├── postgres/               # PostgreSQL data
│   └── odoo/                   # Odoo data (filestore, sessions)
└── addons/                     # Addon mount points
    ├── custom/                 # -> odoo-custom-addons content
    └── third_party/            # -> odoo-third-party-addons content
```

## Prerequisites

- Docker and Docker Compose
- Git
- The companion addon repositories cloned alongside this repo:
  - [odoo-custom-addons](https://github.com/mayiecosmetics/odoo-custom-addons)
  - [odoo-third-party-addons](https://github.com/mayiecosmetics/odoo-third-party-addons)

## Quick Start

### 1. Clone all repositories

```bash
git clone git@github.com:mayiecosmetics/odoo-deployment.git
git clone git@github.com:mayiecosmetics/odoo-custom-addons.git
git clone git@github.com:mayiecosmetics/odoo-third-party-addons.git
```

### 2. Set up environment

```bash
cd odoo-deployment
cp .env.example .env
# Edit .env — set real passwords for POSTGRES_PASSWORD and ODOO_ADMIN_PASSWORD
```

### 3. Start the stack

```bash
docker compose up -d
```

### 4. Access Odoo

- **Web interface:** http://localhost:8069
- **Database manager:** http://localhost:8069/web/database/manager

## Environment Variables

All configuration is controlled via `.env`. One credential set for both PostgreSQL and Odoo:

| Variable | Purpose | Default |
|----------|---------|---------|
| `POSTGRES_DB` | Database name | `postgres` |
| `POSTGRES_USER` | Database user (shared by Postgres and Odoo) | `odoo` |
| `POSTGRES_PASSWORD` | Database password (shared by Postgres and Odoo) | — |
| `ODOO_IMAGE` | Odoo Docker image | `odoo:19.0` |
| `ODOO_PORT` | Host port for Odoo web | `8069` |
| `ODOO_LONGPOLLING_PORT` | Host port for longpolling | `8072` |
| `ODOO_ADMIN_PASSWORD` | Odoo master/admin password | — |
| `BACKUP_RETENTION_DAYS` | Auto-delete backups older than N days | `30` |

## How the Repositories Connect

The deployment repo mounts addon directories into the Odoo container:

```yaml
services:
  odoo:
    volumes:
      - ./addons/custom:/mnt/extra-addons/custom
      - ./addons/third_party:/mnt/extra-addons/third_party
```

The `odoo.conf` includes these paths in `addons_path`:

```ini
addons_path =
    /mnt/extra-addons/custom,
    /mnt/extra-addons/third_party,
    /usr/lib/python3/dist-packages/odoo/addons
```

## Backups

### Create a backup

```bash
./scripts/backup.sh
```

Backups include the PostgreSQL database dump and the full Odoo data directory (filestore, sessions). Stored in `./backups/` with timestamps.

### Restore from backup

```bash
./scripts/restore.sh ./backups/backup_postgres_20260325_120000.tar.gz
```

## Migration to Production (Ubuntu)

This configuration runs identically on macOS and Ubuntu. To migrate:

1. Copy this repo to the server
2. Copy `volumes/` directory (postgres data + odoo data)
3. Create `.env` with production passwords
4. Adjust `odoo.conf` for production: `workers = 4`, `proxy_mode = True`, `list_db = False`
5. Remove or don't copy `docker-compose.override.yml` (disables dev mode)
6. `docker compose up -d`

No structural changes required.

## Branch Strategy

| Branch       | Purpose          |
|-------------|------------------|
| `main`      | Production       |
| `dev`       | Staging/testing  |
| `feature/*` | New features     |
| `hotfix/*`  | Urgent fixes     |

## Related Repositories

| Repository | Description |
|-----------|-------------|
| [odoo-custom-addons](https://github.com/mayiecosmetics/odoo-custom-addons) | Custom Mayie business modules |
| [odoo-third-party-addons](https://github.com/mayiecosmetics/odoo-third-party-addons) | OCA/community/paid modules |
| [odoo-docs](https://github.com/mayiecosmetics/odoo-docs) | Architecture and workflow documentation |
