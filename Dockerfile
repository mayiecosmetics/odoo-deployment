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
USER odoo
