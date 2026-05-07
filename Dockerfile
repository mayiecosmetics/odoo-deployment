FROM odoo:19.0
USER root
COPY config/odoo.conf.template /etc/odoo/odoo.conf.template
RUN apt-get update \
 && apt-get install -y --no-install-recommends gettext-base \
 && pip3 install --no-cache-dir --break-system-packages boto3 \
 && rm -rf /var/lib/apt/lists/*
USER odoo
