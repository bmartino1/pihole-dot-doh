#############################
# PI-Hole DOT DOH - Unbound Builder (Alpine)
#############################
FROM alpine:latest as unbound

ARG UNBOUND_VERSION=1.22.0
ARG UNBOUND_SHA256=c5dd1bdef5d5685b2cedb749158dd152c52d44f65529a34ac15cd88d4b1b3d43
ARG UNBOUND_DOWNLOAD_URL=https://nlnetlabs.nl/downloads/unbound/unbound-1.22.0.tar.gz

WORKDIR /tmp/src

# Create necessary directories for configuration and default files.
RUN mkdir -p /config /temp /etc/cloudflared /etc/unbound/unbound.conf.d /var/lib/unbound /usr/local/etc/unbound

# Install build dependencies (Alpine names).
# We add protobuf-c-dev to support dnstap compilation.
RUN build_deps="curl gcc musl-dev libevent-dev expat-dev nghttp2-dev make openssl-dev protobuf-c-dev" && \
    apk update && apk add --no-cache $build_deps ca-certificates ldns libevent expat && \
    curl -sSL ${UNBOUND_DOWNLOAD_URL} -o unbound.tar.gz && \
    echo "${UNBOUND_SHA256}  unbound.tar.gz" | sha256sum -c - && \
    tar xzf unbound.tar.gz && \
    rm -f unbound.tar.gz && \
    cd unbound-${UNBOUND_VERSION} && \
    addgroup -S unbound && adduser -S -G unbound -h /etc unbound && \
    ./configure \
      --disable-dependency-tracking \
      --with-pthreads \
      --with-username=unbound \
      --with-libevent \
      --with-libnghttp2 \
      --enable-dnstap \
      --enable-tfo-server \
      --enable-tfo-client \
      --enable-event-api \
      --enable-subnet && \
    make -j"$(nproc)" install && \
    apk del $build_deps && \
    rm -rf /tmp/*

#############################
# Final Image: Alpine-based Pi-hole
#############################
FROM alpine:latest
#LABEL maintainer="your-email@example.com"

# Verify folder paths and create directories as needed.
RUN mkdir -p /config /temp /etc/cloudflared /etc/unbound/unbound.conf.d /var/lib/unbound /usr/local/etc/unbound

# Install runtime dependencies.
RUN apk update && apk upgrade && \
    apk add --no-cache \
      bash \
      curl \
      wget \
      git \
      php83 \
      php83-fpm \
      php83-curl \
      php83-json \
      php83-openssl \
      php83-mbstring \
      php83-gd \
      php83-zip \
      php83-phar \
      php83-simplexml \
      lighttpd \
      tzdata \
      sudo \
      nano \
      stubby \
      openssl-dev \
      perl \
      iputils \
      iperf3 \
      bind-tools

# Set default timezone (can be overridden via Docker variable)
ENV TZ=UTC

# -- Remove or comment out the direct Pi-hole install line --
# RUN curl -sSL https://install.pi-hole.net | bash /dev/stdin --unattended

# Copy Unbound binaries and configs from the builder stage (Unbound build).
COPY --from=unbound /usr/local/sbin/unbound* /usr/local/sbin/
COPY --from=unbound /usr/local/lib/libunbound* /usr/local/lib/
COPY --from=unbound /usr/local/etc/unbound/* /usr/local/etc/unbound/

# Copy all scripts (including alpine_patch_pihole_installer.sh) into /temp.
COPY scripts/ /temp

# Create the unbound user and group (if not already created by the installer)
RUN addgroup -S unbound || true && adduser -S -G unbound unbound || true

# Run our Alpine patch script, which downloads, patches, and runs Pi-hole's installer.
RUN chmod +x /temp/alpine_patch_pihole_installer.sh && \
    /temp/alpine_patch_pihole_installer.sh

# Copy install.sh from /temp into /etc/cont-init.d for runtime execution.
RUN cp /temp/install.sh /etc/cont-init.d/10-install.sh && chmod +x /etc/cont-init.d/10-install.sh

# Install s6-overlay for process supervision.
ENV S6_OVERLAY_VERSION=v3.1.5.0
RUN wget -qO- https://github.com/just-containers/s6-overlay/releases/download/${S6_OVERLAY_VERSION}/s6-overlay-amd64.tar.gz \
    | tar zxvf - -C /

# Create a service to run Pi-hole (Lighttpd, PHP-FPM, pihole-FTL).
RUN mkdir -p /etc/services.d/pihole
RUN cp /temp/pihole-run.sh /etc/services.d/pihole/run && chmod +x /etc/services.d/pihole/run

# Expose required ports:
#  - 80/tcp & 443/tcp for the Pi-hole Web UI
#  - 53/tcp & 53/udp for DNS queries
#  - 65 for Pi-hole DHCP
EXPOSE 65 80 443 53/tcp 53/udp

# Make /config a volume for runtime config overrides.
VOLUME ["/config"]

# For debugging/tracking, write a build date file.
RUN echo "$(date '+%d.%m.%Y %T') Built from alpine using pihole image" >> /build_date.info

# Use s6-overlay as our init system.
ENTRYPOINT ["/init"]
