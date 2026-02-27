# Multi-stage Dockerfile to build a newer Squid from source while preserving
# ubuntu/squid-style runtime conventions for drop-in Kubernetes usage.
#
# Compatibility goals:
# - Config path: /etc/squid/squid.conf
# - Binary path: /usr/sbin/squid
# - Default non-root identity aligned with common manifests: 1000:3000

FROM ubuntu:22.04 AS builder
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential autoconf automake libtool libtool-bin libltdl-dev pkg-config ca-certificates \
    wget curl git perl python3 bison flex \
    libssl-dev libkrb5-dev libldap2-dev zlib1g-dev libpcre3-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src
COPY . /src

# Bootstrap only when needed; fail fast if generation/configure fails.
RUN set -eux; \
    chmod +x ./bootstrap.sh || true; \
    if [ ! -x ./configure ]; then ./bootstrap.sh; fi; \
    ./configure \
    --prefix=/usr \
    --sysconfdir=/etc \
    --localstatedir=/var \
    --libexecdir=/usr/lib/squid \
    --with-default-user=squid \
    --with-openssl \
    && make -j"$(nproc)" \
    && make install


FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC
ARG SQUID_UID=1000
ARG SQUID_GID=3000
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates tzdata libssl3 libkrb5-3 libldap-2.5-0 zlib1g libpcre3 \
    && rm -rf /var/lib/apt/lists/*

# Copy installed Squid artifacts from builder
COPY --from=builder /usr /usr
# Provide MIME table at default path expected by this build (--sysconfdir=/etc)
COPY src/mime.conf.default /etc/mime.conf

# Create squid user and runtime directories with configurable UID/GID and
# set ownership at build time. Mounted volumes (PV/PVC) still require
# Kubernetes `fsGroup` and/or an initContainer for ownership fixes.
RUN set -eux; \
    groupadd -g "$SQUID_GID" squid || true; \
    useradd -u "$SQUID_UID" -g "$SQUID_GID" -M -s /sbin/nologin squid || true; \
    mkdir -p /var/cache/squid /var/log/squid /run/squid /etc/squid; \
    ln -sf /etc/mime.conf /etc/squid/mime.conf; \
    chown -R "$SQUID_UID":"$SQUID_GID" /var/cache/squid /var/log/squid /run/squid /etc/squid; \
    chmod -R g+rwX /var/cache/squid /var/log/squid /run/squid /etc/squid

COPY docker-entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 3128
VOLUME ["/var/log/squid", "/var/cache/squid"]
ENTRYPOINT ["entrypoint.sh"]
USER ${SQUID_UID}:${SQUID_GID}
CMD ["-f", "/etc/squid/squid.conf", "-NYC"]
