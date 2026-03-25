# Odoo Deployment — Mayie Cosmetics

Infrastructure repository for the Mayie Cosmetics Odoo ERP deployment.

## Overview

This repository contains everything needed to deploy and manage the Odoo instance:

- Docker Compose configuration
- Odoo server configuration
- Backup and restore scripts
- Nginx reverse proxy configuration
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
│   └── odoo.conf               # Nginx reverse proxy config
├── scripts/
│   ├── backup.sh               # Database + filestore backup
│   └── restore.sh              # Restore from backup
├── volumes/                    # Docker volumes (git-ignored)
│   ├── postgres/               # PostgreSQL data
│   └── filestore/              # Odoo filestore
└── addons/                     # Symlink targets for addon repos
    ├── custom/                 # -> odoo-custom-addons
    └── third_party/            # -> odoo-third-party-addons
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
# Edit .env with your values
```

### 3. Start the stack

```bash
docker compose up -d
```

### 4. Access Odoo

- **Web interface:** http://localhost:8069
- **Database manager:** http://localhost:8069/web/database/manager

## How the Repositories Connect

The deployment repo references the addon repos via Docker volume mounts:

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

Backups are stored in `./backups/` with timestamps: `backup_YYYYMMDD_HHMMSS.tar.gz`

### Restore from backup

```bash
./scripts/restore.sh ./backups/backup_20260325_120000.tar.gz
```

## Branch Strategy

| Branch       | Purpose          |
|-------------|------------------|
| `main`      | Production       |
| `dev`       | Staging/testing  |
| `feature/*` | New features     |
| `hotfix/*`  | Urgent fixes     |

### Workflow

1. Create a feature branch from `dev`
2. Develop and test locally
3. Merge to `dev` for staging
4. Test on staging
5. Merge to `main` for production
6. Tag the release (e.g., `v1.0.0`)

## Version Tagging

Always tag releases on `main`:

```bash
git tag -a v1.0.0 -m "Initial production deployment"
git push origin v1.0.0
```

Tags enable rollback, audit trail, and stable deployments.

## Related Repositories

| Repository | Description |
|-----------|-------------|
| [odoo-custom-addons](https://github.com/mayiecosmetics/odoo-custom-addons) | Custom Mayie business modules |
| [odoo-third-party-addons](https://github.com/mayiecosmetics/odoo-third-party-addons) | OCA/community/paid modules |
| [odoo-docs](https://github.com/mayiecosmetics/odoo-docs) | Architecture and workflow documentation |
