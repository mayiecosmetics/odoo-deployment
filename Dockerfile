FROM odoo:19.0
USER root
COPY config/odoo.conf.template /etc/odoo/odoo.conf.template
RUN apt-get update \
 && apt-get install -y --no-install-recommends gettext-base curl \
 && pip3 install --no-cache-dir --break-system-packages \
        boto3 \
        "fsspec[s3]>=2025.3.0" \
        python-slugify \
 && rm -rf /var/lib/apt/lists/*
USER odoo
