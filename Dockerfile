# Core and Enterprise are a matched pair: the core release below MUST match
# ODOO_ENTERPRISE_REF in docker-compose.yml (nightly 19.0.20261123 <->
# enterprise d1a413a9f of 2026-11-21). A core newer or older than the
# enterprise commit fails to load the registry (outage of 2026-09-15). Bump both
# in the same commit, and change ODOO_ENTERPRISE_REF in Coolify's environment
# too; see "Core/enterprise pin" in README.md.

# =============================================================================
# Stage odoo-core: the official odoo/docker recipe, on a newer nightly package
# =============================================================================
# On 2026-11-23 the newest dated tag on Docker Hub was odoo:19.0-20261112, which
# predates the fix for ODOO-SA-2026-11-23 / CVE-2026-130029. The fix is two
# odoo/odoo commits (8196ff1a of 2026-11-16, 8eb0fdf3 of 2026-11-20); the first
# nightly with both is 19.0.20261121 (19.0.20261120 has only the first, checked
# in the packages). This stage is therefore github.com/odoo/docker,
# 19.0/Dockerfile at commit 0ea197eb (release 20261112), copied step for step
# with these changes only: ODOO_RELEASE is 20261123; the package is downloaded
# over https and checked against the SHA-256 published in its .changes file
# (https://nightly.odoo.com/19.0/nightly/deb/odoo_19.0.20261123_amd64.changes)
# instead of SHA-1; the maintainer LABEL is left out, since Odoo S.A. does not
# maintain this image. entrypoint.sh, wait-for-psql.py and odoo.conf are copied
# unchanged from the same commit into docker/odoo-base/.
# Nightly 19.0.20261123 was built on 2026-11-23 at 02:26 UTC from odoo/odoo 19.0
# at d36b9405f (checked by comparing files of the package with the repository).
#
# When Docker Hub has an odoo:19.0-<date> tag that is new enough, delete this
# stage and docker/odoo-base/, and write `FROM odoo:19.0-<date>` below instead
# of `FROM odoo-core`.
FROM ubuntu:noble AS odoo-core

SHELL ["/bin/bash", "-xo", "pipefail", "-c"]

# Generate locale C.UTF-8 for postgres and general locale data
ENV LANG=en_US.UTF-8

# Retrieve the target architecture to install the correct wkhtmltopdf package
ARG TARGETARCH

# Install some deps, lessc and less-plugin-clean-css, and wkhtmltopdf

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        dirmngr \
        fonts-noto-cjk \
        gnupg \
        libssl-dev \
        node-less \
        python3-magic \
        python3-num2words \
        python3-odf \
        python3-pdfminer \
        python3-pip \
        python3-phonenumbers \
        python3-pyldap \
        python3-qrcode \
        python3-renderpm \
        python3-setuptools \
        python3-slugify \
        python3-vobject \
        python3-watchdog \
        python3-xlrd \
        python3-xlwt \
        xz-utils && \
    if [ -z "${TARGETARCH}" ]; then \
        TARGETARCH="$(dpkg --print-architecture)"; \
    fi; \
    WKHTMLTOPDF_ARCH=${TARGETARCH} && \
    case ${TARGETARCH} in \
    "amd64") WKHTMLTOPDF_ARCH=amd64 && WKHTMLTOPDF_SHA=967390a759707337b46d1c02452e2bb6b2dc6d59  ;; \
    "arm64")  WKHTMLTOPDF_SHA=90f6e69896d51ef77339d3f3a20f8582bdf496cc  ;; \
    "ppc64le" | "ppc64el") WKHTMLTOPDF_ARCH=ppc64el && WKHTMLTOPDF_SHA=5312d7d34a25b321282929df82e3574319aed25c  ;; \
    esac \
    && curl -o wkhtmltox.deb -sSL https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-3/wkhtmltox_0.12.6.1-3.jammy_${WKHTMLTOPDF_ARCH}.deb \
    && echo ${WKHTMLTOPDF_SHA} wkhtmltox.deb | sha1sum -c - \
    && apt-get install -y --no-install-recommends ./wkhtmltox.deb \
    && rm -rf /var/lib/apt/lists/* wkhtmltox.deb

# install latest postgresql-client
RUN echo 'deb http://apt.postgresql.org/pub/repos/apt/ noble-pgdg main' > /etc/apt/sources.list.d/pgdg.list \
    && GNUPGHOME="$(mktemp -d)" \
    && export GNUPGHOME \
    && repokey='B97B0AFCAA1A47F044F244A07FCC7D46ACCC4CF8' \
    && gpg --batch --keyserver keyserver.ubuntu.com --recv-keys "${repokey}" \
    && gpg --batch --armor --export "${repokey}" > /etc/apt/trusted.gpg.d/pgdg.gpg.asc \
    && gpgconf --kill all \
    && rm -rf "$GNUPGHOME" \
    && apt-get update  \
    && apt-get install --no-install-recommends -y postgresql-client \
    && rm -f /etc/apt/sources.list.d/pgdg.list \
    && rm -rf /var/lib/apt/lists/*

# Install rtlcss (on Debian buster)
RUN apt-get update && \
    apt-get install -y --no-install-recommends nodejs npm \
    && npm install -g rtlcss \
    && apt-get purge --autoremove -y npm \
    && rm -rf /var/lib/apt/lists/*

# Install Odoo
ENV ODOO_VERSION=19.0
ARG ODOO_RELEASE=20261123
ARG ODOO_SHA256=b501009a9b8dbf375f69acc42a011fd1dba4b27e5b70c27dacc8478dba715858
RUN curl -o odoo.deb -sSL https://nightly.odoo.com/${ODOO_VERSION}/nightly/deb/odoo_${ODOO_VERSION}.${ODOO_RELEASE}_all.deb \
    && echo "${ODOO_SHA256} odoo.deb" | sha256sum -c - \
    && apt-get update \
    && apt-get -y install --no-install-recommends ./odoo.deb \
    && rm -rf /var/lib/apt/lists/* odoo.deb

# Copy entrypoint script and Odoo configuration file
COPY docker/odoo-base/entrypoint.sh /
COPY docker/odoo-base/odoo.conf /etc/odoo/

# Set permissions and Mount /var/lib/odoo to allow restoring filestore and /mnt/extra-addons for users addons
RUN chown odoo /etc/odoo/odoo.conf \
    && mkdir -p /mnt/extra-addons \
    && chown -R odoo /mnt/extra-addons
VOLUME ["/var/lib/odoo", "/mnt/extra-addons"]

# Expose Odoo services
EXPOSE 8069 8071 8072

# Set the default config file
ENV ODOO_RC=/etc/odoo/odoo.conf

COPY docker/odoo-base/wait-for-psql.py /usr/local/bin/wait-for-psql.py

# Set default user when running the container
USER odoo

ENTRYPOINT ["/entrypoint.sh"]
CMD ["odoo"]

# =============================================================================
# Mayie image: config template, Python stack, security hotfixes
# =============================================================================
FROM odoo-core
USER root
COPY config/odoo.conf.template /etc/odoo/odoo.conf.template
# The S3 stack is pinned exactly, and fsspec and s3fs MUST stay on the same
# version (s3fs requires fsspec==<its own version>.*). With only a lower bound
# on fsspec[s3], pip backtracked and silently selected s3fs 0.4.2 (2020), which
# fsspec itself flags as causing severe performance issues: attachment reads
# from MinIO hung and cron 68 blew the 120s watchdog (2026-09-17). boto3 is held
# at the release aiobotocore's botocore pin allows, not the newest.
# `patch` is installed here, not in the hotfix layer below, so that adding or
# dropping a patch never needs the network.
RUN apt-get update \
 && apt-get install -y --no-install-recommends gettext-base curl patch \
 && pip3 install --no-cache-dir --break-system-packages \
        "boto3==1.43.75" \
        "aiobotocore==3.9.1" \
        "fsspec[s3]==2026.7.0" \
        "s3fs==2026.7.0" \
        python-slugify \
        packaging \
 && rm -rf /var/lib/apt/lists/*
# Security hotfixes on top of the core, one file per advisory in patches/ (each
# file says which upstream commits it carries and when to drop it). There is
# none at the moment: core 19.0.20261123 already contains the fix for
# ODOO-SA-2026-11-23 / CVE-2026-130029 that patches/0001 carried before.
# Kept in its own layer, after the dependency layer above, so that adding or
# dropping a patch never reinstalls the Python stack. An empty patches/ is
# valid (patches/README.md keeps the directory in git).
# `patch -N` never reverses or prompts: a patch that no longer applies (e.g.
# after a core bump that already contains the fix) fails the build, on purpose.
# The last check is a floor for the advisories handled so far: it imports the
# module and asserts the fix is in the code that runs, whether it comes from
# the core or from a patch. Keep each assertion after its patch is dropped, so
# that a core downgrade or a wrong pin cannot bring the hole back unnoticed.
COPY patches/ /tmp/odoo-patches/
RUN set -e; \
    for p in /tmp/odoo-patches/*.patch; do \
        [ -e "$p" ] || continue; \
        echo "Applying $p"; \
        patch -p1 -N --no-backup-if-mismatch -d /usr/lib/python3/dist-packages < "$p"; \
        sed -n 's#^+++ [^/[:space:]]*/\([^[:space:]]*\.py\).*#/usr/lib/python3/dist-packages/\1#p' "$p" \
            | xargs -r python3 -m compileall -q; \
    done; \
    python3 -c "import inspect, odoo.tools.mail as m; s = inspect.getsource(m.html_normalize); assert \"serialized.replace(b'--!>', b'-->')\" in s, 'CVE-2026-130029 fix missing'; assert '(?=[^<>]*>)' in s, 'CVE-2026-130029 refinement (odoo/odoo 8eb0fdf3) missing'; assert 'xlink:href' in m.defs.link_attrs, 'xlink:href fix missing'; print('security floor OK: CVE-2026-130029')"; \
    rm -rf /tmp/odoo-patches
USER odoo
