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

# Install build dependencies and build Unbound from source
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

# Create directories for Pi-hole and Unbound
RUN mkdir -p /config /temp /etc/cloudflared /etc/unbound/unbound.conf.d /var/lib/unbound /usr/local/etc/unbound

# Ensure all scripts are copied to /temp
COPY scripts/ /temp/

# Enable Alpine Edge Repository for required dependencies
RUN echo "http://dl-cdn.alpinelinux.org/alpine/edge/main" >> /etc/apk/repositories && \
    echo "http://dl-cdn.alpinelinux.org/alpine/edge/community" >> /etc/apk/repositories && \
    echo "http://dl-cdn.alpinelinux.org/alpine/edge/testing" >> /etc/apk/repositories && \
    apk update

# Install required dependencies
RUN apk upgrade && \
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
      bind-tools \
      dialog \
      newt \
      procps \
      dhcpcd \
      openrc \
      ncurses

# Set default timezone
ENV TZ=UTC

# Copy Unbound binaries and configs from the builder stage
COPY --from=unbound /usr/local/sbin/unbound* /usr/local/sbin/
COPY --from=unbound /usr/local/lib/libunbound* /usr/local/lib/
COPY --from=unbound /usr/local/etc/unbound/* /usr/local/etc/unbound/

# Create unbound user/group
RUN addgroup -S unbound || true && adduser -S -G unbound unbound || true

# Ensure OpenRC service dependencies are properly configured
RUN touch /etc/runlevels/default/dev && \
    touch /etc/runlevels/default/machine-id && \
    rc-update add dev default || true && \
    rc-update add machine-id default || true

# Fix pihole install script - Set environment variables for unattended mode
ENV TERM=xterm
ENV PIHOLE_SKIP_OS_CHECK=true
ENV PIHOLE_INTERFACE=eth0
ENV IPV4_ADDRESS="0.0.0.0"
ENV INSTALL_WEB_INTERFACE=true
ENV INSTALL_WEB_SERVER=true
ENV PIHOLE_DNS_1=127.1.1.1#5153
ENV PIHOLE_DNS_2=127.2.2.2#5253
ENV QUERY_LOGGING=true
ENV PRIVACY_LEVEL=0
ENV CACHE_SIZE=10000
ENV INSTALL_UNBOUND=false
ENV WEBPASSWORD="piholeAdmin"

# Download Pi-hole install script
RUN curl -sSL "https://gitlab.com/yvelon/pi-hole/-/raw/master/automated%20install/basic-install.sh?ref_type=heads" -o /temp/pihole-install.sh && \
    chmod +x /temp/pihole-install.sh && \

    # Modify install script to ensure environment variables are set
    sed -i '1i\
# Ensure environment variables are set\n\
PIHOLE_INTERFACE="eth0"\n\
IPV4_ADDRESS="0.0.0.0"\n\
INSTALL_WEB_INTERFACE=true\n\
INSTALL_WEB_SERVER=true\n\
PIHOLE_DNS_1="127.1.1.1#5153"\n\
PIHOLE_DNS_2="127.2.2.2#5253"\n\
QUERY_LOGGING=true\n\
PRIVACY_LEVEL=0\n\
CACHE_SIZE=10000\n\
INSTALL_UNBOUND=false\n\
WEBPASSWORD="piholeAdmin"\n\
' /temp/pihole-install.sh && \

    # Force the script into unattended mode
    sed -i 's/^runUnattended=.*/runUnattended=true/' /temp/pihole-install.sh && \
    sed -i 's/^useUpdateVars=.*/useUpdateVars=true/' /temp/pihole-install.sh && \

    # Force DHCP by modifying the section that prompts for static IP
    sed -i 's/chooseInterface/#chooseInterface/' /temp/pihole-install.sh && \
    sed -i 's/setStaticIPv4/#setStaticIPv4/' /temp/pihole-install.sh && \

    # Run the modified installer script
    PIHOLE_SKIP_OS_CHECK=true bash /temp/pihole-install.sh --unattended --disable-install-webserver

# Copy additional install.sh to cont-init.d for runtime tasks (cloudflared/unbound config, etc.)
RUN cp /temp/install.sh /etc/cont-init.d/10-install.sh && chmod +x /etc/cont-init.d/10-install.sh

# Install s6-overlay for process supervision
ENV S6_OVERLAY_VERSION=v3.1.5.0
RUN wget -qO- https://github.com/just-containers/s6-overlay/releases/download/${S6_OVERLAY_VERSION}/s6-overlay-amd64.tar.gz \
    | tar zxvf - -C /

# Ensure Pi-hole service directory exists
RUN mkdir -p /etc/services.d/pihole

# Copy pihole-run.sh correctly from /temp to the services directory
RUN cp /temp/pihole-run.sh /etc/services.d/pihole/run && chmod +x /etc/services.d/pihole/run

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
