#############################
# 1) Unbound Builder Stage (Alpine)
#############################
FROM alpine:latest AS unbound

ARG UNBOUND_VERSION=1.22.0
ARG UNBOUND_SHA256=c5dd1bdef5d5685b2cedb749158dd152c52d44f65529a34ac15cd88d4b1b3d43
ARG UNBOUND_DOWNLOAD_URL=https://nlnetlabs.nl/downloads/unbound/unbound-${UNBOUND_VERSION}.tar.gz

WORKDIR /tmp/src

# Create necessary directories
RUN mkdir -p /config /temp /etc/cloudflared /etc/unbound/unbound.conf.d /var/lib/unbound /usr/local/etc/unbound

# Install build dependencies (Alpine names) and build Unbound from source
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
# 2) Final Image: Alpine-based Pi-hole
#############################
FROM alpine:latest
#LABEL maintainer="your-email@example.com"

# Create directories for Pi-hole and Unbound (DoubleCheck fodler paths for latter)
RUN mkdir -p /config /temp /etc/cloudflared /etc/unbound/unbound.conf.d /var/lib/unbound /usr/local/etc/unbound

#add the scripts to /temp
COPY scripts/ /temp
#ADD scripts /temp

# Install runtime dependencies (Alpine)
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

# Set default timezone (override via Docker env variable if needed)
ENV TZ=UTC

# Copy Unbound binaries and configs from the builder stage
COPY --from=unbound /usr/local/sbin/unbound* /usr/local/sbin/
COPY --from=unbound /usr/local/lib/libunbound* /usr/local/lib/
COPY --from=unbound /usr/local/etc/unbound/* /usr/local/etc/unbound/

# Create unbound user/group if not already existing
RUN addgroup -S unbound || true && adduser -S -G unbound unbound || true

# Clone and run the Alpine-compatible Pi-hole installation script
# The official Pi-hole install script does not support Alpine.
# This custom script ensures necessary dependencies are installed correctly.
RUN git clone --depth=1 https://gitlab.com/yvelon/pi-hole.git /tmp/pi-hole && \
    bash /tmp/pi-hole/install.sh && \
    rm -rf /tmp/pi-hole

# Copy additional install.sh to cont-init.d for runtime tasks (cloudflared/unbound config, etc.)
RUN cp /temp/install.sh /etc/cont-init.d/10-install.sh && chmod +x /etc/cont-init.d/10-install.sh

# Install s6-overlay for process supervision
ENV S6_OVERLAY_VERSION=v3.1.5.0
RUN wget -qO- https://github.com/just-containers/s6-overlay/releases/download/${S6_OVERLAY_VERSION}/s6-overlay-amd64.tar.gz \
    | tar zxvf - -C /

# Create a service for Pi-hole (Lighttpd, PHP-FPM, pihole-FTL)
RUN mkdir -p /etc/services.d/pihole
COPY temp/pihole-run.sh /etc/services.d/pihole/run
RUN chmod +x /etc/services.d/pihole/run

# Expose Pi-hole ports:
#   - 80/tcp & 443/tcp for the Pi-hole Web UI
#   - 53/tcp & 53/udp for DNS queries
#   - 67/udp for Pi-hole DHCP service
EXPOSE 80 443 53/tcp 53/udp 67/udp

# Make /config a volume for runtime config overrides
VOLUME ["/config"]

# Write a build date file for debugging/tracking
RUN echo "$(date '+%d.%m.%Y %T') Built from alpine using pihole image" >> /build_date.info

# Use s6-overlay as init
ENTRYPOINT ["/init"]
