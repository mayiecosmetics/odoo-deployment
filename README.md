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

## Core/enterprise pin

**The Odoo core image and the Enterprise addons are a matched pair. Bump them together or not at all.**

| Where | What | Current value |
|-------|------|---------------|
| `Dockerfile` | `FROM odoo:19.0-20260528` | dated core build |
| `docker-compose.yml` → `enterprise-fetcher` | `ODOO_ENTERPRISE_REF` | `88d2e934eaf7eb37f72732bc1b9c1593a3ba1577` (2026-06-06) |

Enterprise addons import from core and vice-versa. A core build newer or older
than the enterprise commit fails to load the registry — this caused the outage
of 2026-09-15. When upgrading, change **both** lines in the **same commit**.

### Gotchas

- **Coolify's UI wins.** `ODOO_ENTERPRISE_REF` is written as `${ODOO_ENTERPRISE_REF:-<sha>}`,
  so the compose default only applies when the variable is *unset*. If someone sets
  `ODOO_ENTERPRISE_REF` in Coolify's environment-variables screen, that value silently
  overrides this repo and the pair desyncs with nothing in git to show for it.
  Before debugging a registry failure, check Coolify's env screen first.
  The same applies to `ODOO_VERSION`, `THIRD_PARTY_BRANCH` and `CUSTOM_BRANCH`.
- **The fetchers reset the addon volumes on every `compose up`.** `enterprise-fetcher`,
  `third-party-fetcher` and `custom-fetcher` run `git reset --hard` + `git clean -fd`
  against `enterprise-addons`, `third-party-addons` and `custom-addons`. Anything
  hand-edited inside those volumes is destroyed on the next deploy — patch the source
  repo instead. Third-party and custom track their **branch heads**, so a merge into
  `main` ships on the next restart, planned or not.
- **Fetch failures are tolerated, on purpose.** If the pinned enterprise commit is
  already in the volume, the fetcher does not touch the network at all, so an expired
  `ODOO_ENTERPRISE_GITHUB_TOKEN` or a GitHub outage cannot block a restart. If a fetch
  *is* needed and fails while the volume already holds a checkout, the fetcher logs a
  loud `WARNING` and exits 0 rather than taking the stack down with it (`odoo` depends
  on the fetchers with `condition: service_completed_successfully`). **Read the fetcher
  logs after a deploy** — a warning there means the addons may not match the pinned core.
  A hard failure happens only when there is nothing in the volume to fall back to.

### Bumping the pair

1. Pick the new dated core tag, e.g. `odoo:19.0-<YYYYMMDD>`.
2. Find the `odoo/enterprise` commit on branch `19.0` from the same day.
3. Edit `Dockerfile` (`FROM`) and `docker-compose.yml` (`ODOO_ENTERPRISE_REF` default).
4. Make sure no override exists in Coolify, then redeploy and rebuild the image.

## Database backups (`db-backup` service)

`pg_dumpall` runs every `BACKUP_INTERVAL_HOURS` into the MinIO `BACKUP_BUCKET`.
The dump is written to a local temp file and only uploaded once it has passed
three checks: the `pg_dumpall | gzip` pipeline exited 0 (`set -o pipefail` —
without it busybox reports only `rclone`'s status and a truncated dump is stored
as a good backup), `gzip -t` validates the archive, and the file is at least
`BACKUP_MIN_BYTES` (default 1 MiB). A failed check uploads nothing, leaves the
previous good backup untouched, logs an error and retries after
`BACKUP_RETRY_SECONDS` (default 600) instead of crashing into a restart loop.

| Variable | Purpose | Default |
|----------|---------|---------|
| `BACKUP_INTERVAL_HOURS` | Hours between backups | `24` |
| `BACKUP_RETENTION_DAYS` | Prune backups older than N days | `30` |
| `BACKUP_MIN_BYTES` | Reject dumps smaller than this | `1048576` |
| `BACKUP_RETRY_SECONDS` | Wait after a failed backup | `600` |

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
