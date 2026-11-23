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
├── Dockerfile                  # Odoo image: core (stage odoo-core) + Mayie layers
├── docker/odoo-base/           # entrypoint.sh, wait-for-psql.py, odoo.conf of the official image
├── patches/                    # Security hotfixes on top of the core (may hold none)
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
| `ODOO_LIST_DB` | Database manager and database listing (`/web/database/*`, RPC service `db`) | `True` |
| `BACKUP_RETENTION_DAYS` | Auto-delete backups older than N days | `30` |

### `ODOO_LIST_DB` must be `False` in production

The default `True` is for local development, where the database manager creates
the first database. In production it is set to **`False` in Coolify's environment
variables** (since 2026-11-23). With `True`, `https://erp.mayie.ro/web/database/manager`
offered backup, restore, duplicate, delete and "set master password" to anyone on
the internet, guarded only by the master password, and `/web/database/list` returned
the database name without any login.

`False` is safe here because the Postgres server holds a single Odoo database
(`odoo`; the `postgres` maintenance database is ignored), so Odoo selects it on its
own and nobody needs the selector. Check after any change to the environment:

```bash
curl -s -X POST https://erp.mayie.ro/web/database/list \
     -H 'Content-Type: application/json' -d '{"jsonrpc":"2.0","method":"call","params":{}}'
# expected: an "Access Denied" error, not ["odoo"]
```

## Core/enterprise pin

**The Odoo core and the Enterprise addons are a matched pair. Bump them together or not at all.**

| Where | What | Current value |
|-------|------|---------------|
| `Dockerfile`, stage `odoo-core` | `ODOO_RELEASE`, `ODOO_SHA256` | nightly package `odoo_19.0.20261123_all.deb`, built 2026-11-23 02:26 UTC from `odoo/odoo` 19.0 at `d36b9405f` |
| `docker-compose.yml` → `enterprise-fetcher` | `ODOO_ENTERPRISE_REF` | `d1a413a9f50bf97212e8d7969ba59616f098b9e5` (2026-11-21), the head of `odoo/enterprise` 19.0 when that core was built |
| Coolify → Environment Variables | `ODOO_ENTERPRISE_REF` | must hold the same commit as the compose default, because it overrides it |

Enterprise addons import from core and vice-versa. A core build newer or older
than the enterprise commit fails to load the registry — this caused the outage
of 2026-09-15. When upgrading, change **both** lines in the **same commit**.

Previous pair, until the upgrade of November 2026: `FROM odoo:19.0-20260528` with
enterprise `88d2e934eaf7eb37f72732bc1b9c1593a3ba1577` (2026-06-06).

### Why the core is built from a nightly package

The upgrade had to reach a core that contains the fix for ODOO-SA-2026-11-23 (nightly
19.0.20261121 or later), and on 2026-11-23 the newest dated tag on Docker Hub was
`odoo:19.0-20261112`. The `odoo-core` stage of the `Dockerfile` is therefore the
official recipe (`odoo/docker`, `19.0/Dockerfile` at `0ea197eb`) with a newer
`ODOO_RELEASE`, downloaded over https and checked against the SHA-256 from the
package's `.changes` file. Its three helper files are in `docker/odoo-base/`,
unchanged. `https://nightly.odoo.com/19.0/nightly/deb/` still held every 19.0 build
since 2025-09-16 on 2026-11-23, so a rebuild without cache finds the same package,
and the checksum guarantees it is the same file.

When Docker Hub publishes a dated tag that is new enough, delete the stage and
`docker/odoo-base/`, and write `FROM odoo:19.0-<date>` instead of `FROM odoo-core`.

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

1. Pick the core. If Docker Hub has a dated tag `odoo:19.0-<YYYYMMDD>` that is new
   enough, use it in `FROM`. Otherwise take a nightly package from
   `https://nightly.odoo.com/19.0/nightly/deb/`: set `ODOO_RELEASE`, and `ODOO_SHA256`
   from the `Checksums-Sha256` line of `odoo_19.0.<date>_all.deb` in the
   `odoo_19.0.<date>_amd64.changes` file next to it.
2. Find the enterprise commit: the head of `odoo/enterprise` `19.0` when the core was
   built (the `Date:` line of the `.changes` file):
   `gh api "repos/odoo/enterprise/commits?sha=19.0&until=<ISO time>&per_page=1"`.
   **Then check it.** On `odoo/odoo` and `odoo/enterprise` the commit date is when the
   merge bot staged a batch, not when it pushed it, so a commit dated before the build
   can be missing from it (`odoo/odoo` `3535c63c` is dated 01:33 UTC on 2026-11-23 and
   is not in the 02:26 build). Walk the first parents from a commit dated after the
   build back to your candidate; every commit in between must be dated after the build.
   To see which `odoo/odoo` commit a package holds, compare a file that a recent commit
   changes with the copy in the package.
3. Edit the `Dockerfile` and the `ODOO_ENTERPRISE_REF` default in `docker-compose.yml`
   in the same commit.
4. Rehearse on a copy of the production database (see "Rehearsing an upgrade").
5. Before deploying, set `ODOO_ENTERPRISE_REF` in Coolify's environment to the new
   commit. On 2026-11-23 it **did** carry `ODOO_ENTERPRISE_REF=88d2e934…`, so without
   this step the bump is silently ignored. Then follow "Upgrading production".
6. Delete every file in `patches/` whose header says the new build already contains
   it. A patch that is already in the core fails the image build on purpose. Keep the
   assertions of the last build step (see "Security hotfixes").

### Rehearsing an upgrade

Run the upgrade first on a fresh copy of the production database, on the laptop, in
the test harness of `odoo-custom-addons` (branch `odoo-test-harness`,
`scripts/odoo-test/`, with a unique `ODOO_TEST_PROJECT`). What the rehearsal of
November 2026 needed, besides the harness itself:

- **The copy.** `docker exec <db> pg_dump -U odoo -d odoo -Fc`, streamed over `ssh` to
  a file outside every repository. It holds customer data: it never goes into a
  commit, a test or a report, and it is deleted at the end with the compose project.
- **No way out.** A compose override gives the project network `internal: true`, so
  Odoo reaches Postgres and nothing else. The copy holds the real Shopify, Nexus,
  Trendyol, SMTP and S3 credentials; no upgrade step should get a chance to use them.
  Before the first Odoo run, also `update ir_cron set active = false`, and the same for
  `ir_mail_server` and `fetchmail_server`.
- **Attachments.** The `fs_storage` record with code `s3` (Hetzner, default storage for
  attachments) takes its settings from the environment. Without them `-u all` stops at
  the first menu icon it rewrites (`InvalidRegionError: '$HETZNER_S3_REGION'`). For the
  copy only, point it at the local filestore through the container environment; the
  database rows stay untouched:

  ```bash
  SERVER_ENV_CONFIG='[fs_storage.s3]
  protocol = odoofs
  options = {}
  eval_options_from_env = False
  directory_path =
  '
  ```
- **A baseline.** Run the same steps with the current pair on a second copy. Only the
  difference between the two runs says what the new pair changes (new warnings,
  schema, duration).

The steps on each copy: start once without `-u` (`--stop-after-init --no-http`: the
registry production loads between the deploy and `-u all`), then
`-u all --stop-after-init --no-http --max-cron-threads=0`, then an HTTP check (login
page, asset bundles, one PDF report). Compare the schema of the two upgraded copies
(columns, indexes, constraints) and the `active` flag of crons, views and rules
against the untouched copy.

Rehearsal of 2026-11-23 (core 19.0.20261123 + enterprise `d1a413a9f`, production copy
of 20:50 UTC, custom addons `bb524a9`, third-party `d9f9cb9`): the registry loads on
the old data without `-u`; `-u all` passes in 170 s (172 s with the current pair) with
the same 92 warnings and the same `studio_customization` error as the current pair;
the schema only gains 16 indexes and one foreign key changes to `ON DELETE CASCADE`;
`-u all` installs the new auto-install module `account_iso20022_account_accountant`
and changes no cron's `active` flag compared to production. Invoices are now rendered
in the invoice's company (upstream change in `account`), so a company whose default
paper format is a label prints its invoices on labels (see "Upgrading production").

## Upgrading production

Needs Tudor's explicit go-ahead in the conversation where it is done, in a quiet hour.
Everything below runs on the server (`ssh hetzner`). Container names change at every
deploy, so look them up again after it.

```bash
ODOO=$(docker ps --format '{{.Names}}' | grep '^odoo-w75tkzcbr7om152wupubem1r' | head -1)
DB=$(docker ps --format '{{.Names}}' | grep '^db-w75tkzcbr7om152wupubem1r' | head -1)
TS=$(date -u +%Y%m%dT%H%M%SZ)
```

**Before the window** (no downtime):

0. Printing must stay exactly as it is (Tudor, 2026-11-23). Two things would change it,
   both rehearsed on 21 real documents and fixed without touching the companies, the
   AWB labels or the shelf labels:
   - Invoices are now rendered in the invoice's company, and MAYIE COSMETICS S.R.L.
     (company 2) has the Studio label format `Etichetă 100×100` as its default paper
     format: its invoices would print on 100×100 mm pages (7 pages instead of 2 of A4).
     The two invoice reports get the A4 format they print with today
     (`base.paperformat_euro`) as their own format (step 1).
   - `-u all` rewrites the report templates from the module files: Odoo's newer
     versions of the address block, the folder layout, the invoice, the sale order and
     the invoice lots table, and it would undo the edits made in the database on
     2026-10-04 to `stock.report_picking` (compact table) and
     `account.report_invoice_document`. These six views get back the
     production version after `-u all` and are marked `noupdate`, so a later `-u`
     leaves them alone too (steps 1 and 5). To take Odoo's versions later: set
     `noupdate = false` on their `ir_model_data` rows and update the module.
1. Backup, the list of disabled crons to compare with afterwards, a copy of the six
   report views as they print today, and the A4 format on the invoice reports:

   ```bash
   docker exec "$DB" pg_dump -U odoo -d odoo -Fc > /root/odoo_pre_upgrade_$TS.dump
   chmod 600 /root/odoo_pre_upgrade_$TS.dump
   docker exec -i "$DB" pg_restore -l < /root/odoo_pre_upgrade_$TS.dump | wc -l   # tens of thousands, not 0
   docker exec "$DB" psql -U odoo -d odoo -At -c "select id from ir_cron where not active order by id" > /root/odoo_pre_upgrade_inactive_crons_$TS.txt
   docker exec -i "$DB" psql -U odoo -d odoo -At <<'SQL'
   create table mayie_upgrade_print_views as
     select v.id, d.module || '.' || d.name as xmlid, v.arch_db
       from ir_ui_view v join ir_model_data d on d.model = 'ir.ui.view' and d.res_id = v.id
      where d.module || '.' || d.name in ('web.address_layout', 'web.external_layout_folder',
            'account.report_invoice_document', 'sale.report_saleorder_document',
            'stock.report_picking', 'stock_account.stock_account_report_invoice_document');
   select count(*) from mayie_upgrade_print_views;                                   -- 6
   update ir_act_report_xml set paperformat_id = (select res_id from ir_model_data where module = 'base' and name = 'paperformat_euro')
    where report_name in ('account.report_invoice_with_payments', 'account.report_invoice');  -- UPDATE 2
   SQL
   ```
2. Fetch the new enterprise commit into the volume (this also proves the GitHub token
   works) and tag the current one, so that the deploy and a rollback both take the
   offline fast path of `enterprise-fetcher`. The checkout Odoo runs from is not touched:

   ```bash
   docker run --rm -v w75tkzcbr7om152wupubem1r_enterprise-addons:/enterprise --entrypoint sh alpine/git:latest -c '
     cd /enterprise && G="git -c safe.directory=/enterprise"
     $G tag -f pre-upgrade-88d2e934 88d2e934eaf7eb37f72732bc1b9c1593a3ba1577
     $G fetch -q --depth 1 origin d1a413a9f50bf97212e8d7969ba59616f098b9e5 >/dev/null 2>&1
     $G cat-file -e "d1a413a9f50bf97212e8d7969ba59616f098b9e5^{commit}" && echo "enterprise d1a413a9 present" || echo "FETCH FAILED: renew ODOO_ENTERPRISE_GITHUB_TOKEN first"'
   ```
3. In Coolify → the odoo-deployment app → Environment Variables, set
   `ODOO_ENTERPRISE_REF` to `d1a413a9f50bf97212e8d7969ba59616f098b9e5` and save, without
   redeploying.

**The window** (about 5–7 minutes without service; plan 30 minutes in all):

4. Merge the upgrade branch into `main`. Coolify builds the image first (about 5 minutes
   on the Mac; the old containers keep serving meanwhile; a failed build changes
   nothing), then replaces the containers. Then check the pair before anything else:

   ```bash
   ODOO=$(docker ps --format '{{.Names}}' | grep '^odoo-w75tkzcbr7om152wupubem1r' | head -1)
   docker exec "$ODOO" dpkg-query -W odoo                          # odoo 19.0.20261123
   docker exec "$ODOO" cat /mnt/extra-addons/enterprise/.git/HEAD  # d1a413a9f50bf97212e8d7969ba59616f098b9e5
   docker logs "$(docker ps -a --format '{{.Names}}' | grep '^enterprise-fetcher-w75tkzcbr7om152wupubem1r' | head -1)" 2>&1 | tail -3
   ```

   Any other version or HEAD, or a `WARNING` in the fetcher log: stop and roll back.
5. `-u all`. The schema change is indexes only, so the running server copes with the
   old data until it is done (rehearsed: registry loads without `-u`). About 3 minutes
   (170 s on the copy):

   ```bash
   docker top "$ODOO" -o pid,etime,args | grep -E 'shell|stop-after-init'   # must print nothing
   time docker exec "$ODOO" odoo -c /tmp/odoo.conf -d odoo -u all --stop-after-init --no-http --max-cron-threads=0 --log-level=info > /root/odoo_u_all_$TS.log 2>&1; echo "exit=$?"
   grep -E ' (ERROR|CRITICAL) ' /root/odoo_u_all_$TS.log   # only "Some modules are not loaded ... ['studio_customization']"
   docker exec -i "$DB" psql -U odoo -d odoo -At <<'SQL'
   update ir_ui_view v set arch_db = s.arch_db from mayie_upgrade_print_views s where v.id = s.id;   -- UPDATE 6
   update ir_model_data d set noupdate = true from mayie_upgrade_print_views s
    where d.model = 'ir.ui.view' and d.res_id = s.id;                                                -- UPDATE 6
   drop table mayie_upgrade_print_views;
   select count(*) from ir_act_report_xml where paperformat_id is not null
      and report_name in ('account.report_invoice_with_payments', 'account.report_invoice');       -- 2
   SQL
   docker restart -t 30 "$ODOO"
   ```
6. Checks: `https://erp.mayie.ro/web/login` answers 200; the Odoo log since the restart
   has no `ERROR` besides `studio_customization`; the disabled crons are the same as in
   `/root/odoo_pre_upgrade_inactive_crons_$TS.txt`; crons run again within 10 minutes
   (`select count(*) from ir_cron where lastcall > now() - interval '10 minutes'`); an
   invoice of MAYIE COSMETICS prints on A4; the security floor holds:
   `docker exec "$ODOO" python3 -c "import inspect, odoo.tools.mail as m; s = inspect.getsource(m.html_normalize); assert \"serialized.replace(b'--!>', b'-->')\" in s and '(?=[^<>]*>)' in s; print('CVE-2026-130029 fix present')"`.

**Rollback** (if step 4, 5 or 6 fails; about 15 minutes). `-u all` changes the
database (module versions, a new module, indexes, rules), so going back means the
code **and** the backup. Whatever was written after the backup is lost, so decide
quickly.

```bash
docker stop -t 30 "$ODOO"
docker exec "$DB" psql -U odoo -d postgres -c "select pg_terminate_backend(pid) from pg_stat_activity where datname = 'odoo' and pid <> pg_backend_pid();"
docker exec "$DB" psql -U odoo -d postgres -c "ALTER DATABASE odoo RENAME TO odoo_failed_upgrade_$TS;"
docker exec "$DB" createdb -U odoo -O odoo odoo
docker cp /root/odoo_pre_upgrade_$TS.dump "$DB":/tmp/restore.dump
docker exec "$DB" pg_restore -U odoo -d odoo --no-owner -j 2 /tmp/restore.dump
docker exec "$DB" rm /tmp/restore.dump
```

Then set `ODOO_ENTERPRISE_REF` back to `88d2e934eaf7eb37f72732bc1b9c1593a3ba1577` in
Coolify, revert the merge on `main` (`git revert -m 1 <merge commit>`, push: Coolify
deploys the previous `Dockerfile`, which carries the CVE-2026-130029 patch again),
and check as in step 6. Drop `odoo_failed_upgrade_$TS` once it is no longer needed.

## Security hotfixes (`patches/`)

Docker Hub's `odoo:19.0-<date>` tags lag the nightly builds by days to weeks, and
moving the core/enterprise pair is a planned upgrade, not something to do in a hurry.
When Odoo publishes a security advisory that affects the pinned build, the fix is
carried as a patch on top of the pin until the next planned bump.

- One file per advisory in `patches/`, applied at image build with
  `patch -p1 -N -d /usr/lib/python3/dist-packages` (see `Dockerfile`). The header of
  each file lists the upstream commits it carries and the first core build that
  already contains them.
- The build fails if a patch does not apply, and the last build step imports the
  patched module and asserts the fix is live. A green build means the fix is in the
  running code.
- `patches/` may hold no patch at all; `patches/README.md` keeps the directory in git.
- The assertions of the last build step are a floor for every advisory handled so
  far, whether the fix comes from the core or from a patch. They stay when a patch is
  dropped, so that a wrong pin or a core downgrade fails the build instead of quietly
  reopening the hole.
- Advisories arrive by email from `security-noreply@odoo.com` (Enterprise
  subscription). The full text is on `https://www.odoo.com/security-advisories`,
  behind the Enterprise subscription code. It names the affected component but not
  the fixing commit: look at the recent history of that file on `odoo/odoo` `19.0`.

No patch is carried at the moment. Patches carried so far:

| Patch | Advisory | Carried | Dropped |
|-------|----------|---------|---------|
| `0001-CVE-2026-130029-html-normalize.patch` | ODOO-SA-2026-11-23, stored XSS through the HTML sanitizer on libxml2 < 2.10 | from 2026-11-23, on core `19.0-20260528` | with the bump to core `19.0.20261123`, which contains the fix (upstream since `19.0.20261121`) |

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

## Discuss calls: STUN/TURN relay (`coturn` service)

Discuss audio/video calls are peer-to-peer WebRTC. Out of the box Odoo only
knows Google's public STUN servers, so a participant behind a strict NAT or
firewall (corporate network, some mobile carriers, hotel Wi-Fi) joins the call
with no audio or video. `coturn` relays media for those participants; everyone
else still connects directly and costs this server nothing.

**Ports** (published by Docker, so they bypass ufw like Traefik's 80/443):
`3478/udp`, `3478/tcp`, relay range `49160-49219/udp`. The server also sits
behind a **Hetzner Cloud Firewall** (Cloud Console → Firewalls) that drops
everything except what it lists; these three rules have to be open there too,
or coturn runs but nothing reaches it.

**Password:** `SERVICE_PASSWORD_COTURN`, a Coolify magic variable generated on
the first deploy (Coolify → the odoo-deployment app → Environment Variables).
User name is `odoo`.

**Odoo side** (Settings → Technical → Discuss → ICE servers, debug mode). Odoo
sends at most 5 entries to the browser; once any exist they replace the Google
defaults:

| Type | URI | Username / credential |
|------|-----|-----------------------|
| `stun:` | `erp.mayie.ro:3478` | — |
| `turn:` | `erp.mayie.ro:3478?transport=udp` | `odoo` / the password |
| `turn:` | `erp.mayie.ro:3478?transport=tcp` | `odoo` / the password |
| `stun:` | `stun1.l.google.com:19302` | — (fallback if coturn is down) |

**Rotating the password:** change `SERVICE_PASSWORD_COTURN` in Coolify,
redeploy, then update both `turn:` records. Odoo gives the credential to every
browser in a call, guests included, so rotate it if it leaks into the wrong
hands; the coturn flags (private peers denied, no TCP relay, quotas) keep a
leaked credential from reaching anything inside the server.

**Known limits:**
- No TURN over TLS on 443 (Traefik owns 443). A network that allows only
  HTTPS out will still fail; TURN over TCP 3478 covers most of the rest.
- Only IPv4 relays (the container has no public IPv6).

Relay-to-relay (both participants on TURN) works because coturn maps its own
`--external-ip` back to the container address and relays internally; the
compose file allows exactly that address through the `10.0.0.0/8` deny.

**Smoke test** from any machine outside the server (allocation should
succeed; `-e` is only the peer address the test sends to):

```bash
docker run --rm --entrypoint turnutils_uclient coturn/coturn:4.18.0 -u odoo -w '<password>' -n 1 -m 1 -e 8.8.8.8 erp.mayie.ro
```

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
