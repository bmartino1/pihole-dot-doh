#############################
# 1) Unbound Builder Stage (Alpine)
#############################
FROM alpine:latest as unbound

ARG UNBOUND_VERSION=1.22.0
ARG UNBOUND_SHA256=c5dd1bdef5d5685b2cedb749158dd152c52d44f65529a34ac15cd88d4b1b3d43
ARG UNBOUND_DOWNLOAD_URL=https://nlnetlabs.nl/downloads/unbound/unbound-1.22.0.tar.gz

WORKDIR /tmp/src

# Create necessary directories
RUN mkdir -p /config /temp /etc/cloudflared /etc/unbound/unbound.conf.d /var/lib/unbound /usr/local/etc/unbound

# Install build dependencies
RUN build_deps="curl gcc musl-dev libevent-dev expat-dev libnghttp2-dev make openssl-dev" && \
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
    make -j$(nproc) install && \
    apk del $build_deps && \
    rm -rf /tmp/*

#############################
# 2) Final Image: Alpine-based Pi-hole
#############################
FROM alpine:latest
#LABEL maintainer="your-email@example.com"

# Create directories
RUN mkdir -p /config /temp /etc/cloudflared /etc/unbound/unbound.conf.d /var/lib/unbound /usr/local/etc/unbound

# Install runtime dependencies (Alpine)
RUN apk update && apk upgrade && \
    apk add --no-cache \
      bash \
      curl \
      wget \
      git \
      php7 \
      php7-fpm \
      php7-curl \
      php7-json \
      php7-openssl \
      php7-mbstring \
      php7-gd \
      php7-zip \
      php7-phar \
      php7-simplexml \
      lighttpd \
      tzdata \
      sudo \
      nano \
      stubby \
      openssl-dev \
      perl

# Set default timezone (override with -e TZ=XXX if needed)
ENV TZ=UTC

# Install Pi-hole v6 instance non-interactively
RUN curl -sSL https://install.pi-hole.net | bash /dev/stdin --unattended

# Copy Unbound from builder stage
COPY --from=unbound /usr/local/sbin/unbound* /usr/local/sbin/
COPY --from=unbound /usr/local/lib/libunbound* /usr/local/lib/
COPY --from=unbound /usr/local/etc/unbound/* /usr/local/etc/unbound/

# Copy your scripts (install.sh, pihole-run.sh, unbound.sh, stubby.yml, etc.) to /temp
COPY scripts/ /temp

# Create unbound user/group if not present
RUN addgroup -S unbound || true && adduser -S -G unbound unbound || true

# Copy install.sh into s6-overlay's cont-init.d so it runs at container startup
COPY /temp/install.sh /etc/cont-init.d/10-install.sh
RUN chmod +x /etc/cont-init.d/10-install.sh

# Install s6-overlay for process supervision
ENV S6_OVERLAY_VERSION=v3.1.5.0
RUN wget -qO- https://github.com/just-containers/s6-overlay/releases/download/${S6_OVERLAY_VERSION}/s6-overlay-amd64.tar.gz \
    | tar zxvf - -C /

# Create a service to run Pi-hole (Lighttpd, PHP-FPM, pihole-FTL)
RUN mkdir -p /etc/services.d/pihole
COPY /temp/pihole-run.sh /etc/services.d/pihole/run
RUN chmod +x /etc/services.d/pihole/run

# Expose ports:
#  - 80/tcp & 443/tcp for Pi-hole Web UI
#  - 53/tcp & 53/udp for DNS
#  - 65 for Pi-hole DHCP
EXPOSE 65 80 443 53/tcp 53/udp

# Make /config a volume for overrides
VOLUME ["/config"]

# For debugging/tracking
RUN echo "$(date '+%d.%m.%Y %T') Built from alpine using pihole image" >> /build_date.info

# Use s6-overlay as init
ENTRYPOINT ["/init"]
