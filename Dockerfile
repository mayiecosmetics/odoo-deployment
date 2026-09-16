# Core is pinned to a dated build: it MUST match ODOO_ENTERPRISE_REF in
# docker-compose.yml (19.0-20260528 <-> enterprise 88d2e934e). A floating
# `odoo:19.0` tag pulled at rebuild time silently changes the core while the
# enterprise pin stays put (or vice-versa) and the registry fails to load.
FROM odoo:19.0-20260528
USER root
COPY config/odoo.conf.template /etc/odoo/odoo.conf.template
RUN apt-get update \
 && apt-get install -y --no-install-recommends gettext-base curl \
 && pip3 install --no-cache-dir --break-system-packages \
        boto3 \
        "fsspec[s3]>=2025.3.0" \
        python-slugify \
        packaging \
 && rm -rf /var/lib/apt/lists/*
USER odoo
