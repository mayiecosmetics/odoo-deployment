# Core is pinned to a dated build: it MUST match ODOO_ENTERPRISE_REF in
# docker-compose.yml (19.0-20260528 <-> enterprise 88d2e934e). A floating
# `odoo:19.0` tag pulled at rebuild time silently changes the core while the
# enterprise pin stays put (or vice-versa) and the registry fails to load.
FROM odoo:19.0-20260528
USER root
COPY config/odoo.conf.template /etc/odoo/odoo.conf.template
# The S3 stack is pinned exactly, and fsspec and s3fs MUST stay on the same
# version (s3fs requires fsspec==<its own version>.*). With only a lower bound
# on fsspec[s3], pip backtracked and silently selected s3fs 0.4.2 (2020), which
# fsspec itself flags as causing severe performance issues: attachment reads
# from MinIO hung and cron 68 blew the 120s watchdog (2026-09-17). boto3 is held
# at the release aiobotocore's botocore pin allows, not the newest.
RUN apt-get update \
 && apt-get install -y --no-install-recommends gettext-base curl \
 && pip3 install --no-cache-dir --break-system-packages \
        "boto3==1.43.75" \
        "aiobotocore==3.9.1" \
        "fsspec[s3]==2026.7.0" \
        "s3fs==2026.7.0" \
        python-slugify \
        packaging \
 && rm -rf /var/lib/apt/lists/*
# Security hotfixes on top of the pinned core, one file per advisory in
# patches/ (each file says which upstream commits it carries and when to drop
# it). Currently: ODOO-SA-2026-11-23 / CVE-2026-130029, stored XSS through the
# HTML sanitizer. Docker Hub had no fixed 19.0 image on 2026-11-23 (newest tag
# 19.0-20261112 predates the fix), so the fix is applied here instead.
# Kept in its own layer, after the dependency layer above, so that adding or
# dropping a patch never reinstalls the Python stack.
# `patch -N` never reverses or prompts: a patch that no longer applies (e.g.
# after a core bump that already contains the fix) fails the build, on purpose.
# The last check imports the patched module, so a build only succeeds when the
# running code really carries the fix.
COPY patches/ /tmp/odoo-patches/
RUN set -e; \
    apt-get update; \
    apt-get install -y --no-install-recommends patch; \
    rm -rf /var/lib/apt/lists/*; \
    for p in /tmp/odoo-patches/*.patch; do \
        echo "Applying $p"; \
        patch -p1 -N --no-backup-if-mismatch -d /usr/lib/python3/dist-packages < "$p"; \
    done; \
    python3 -m compileall -q /usr/lib/python3/dist-packages/odoo/tools/mail.py; \
    python3 -c "import inspect, odoo.tools.mail as m; s = inspect.getsource(m.html_normalize); assert \"serialized.replace(b'--!>', b'-->')\" in s, 'CVE-2026-130029 fix missing'; assert 'xlink:href' in m.defs.link_attrs, 'xlink:href fix missing'; print('security hotfixes active')"; \
    rm -rf /tmp/odoo-patches
USER odoo
