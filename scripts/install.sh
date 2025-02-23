#!/bin/sh
set -eux

# Clean stubby config.
mkdir -p /etc/stubby
rm -f /etc/stubby/stubby.yml

# Determine architecture using uname.
ARCH=$(uname -m)
case "$ARCH" in
    aarch64|arm64)
        CF_PACKAGE="cloudflared-linux-arm64.apk"
        ;;
    arm)
        CF_PACKAGE="cloudflared-linux-arm.apk"
        ;;
    amd64|x86_64)
        CF_PACKAGE="cloudflared-linux-amd64.apk"
        ;;
    *)
        echo "Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

# For Alpine, cloudflared is installed in the Dockerfile.
echo "$(date "+%d.%m.%Y %T") cloudflared version: $(/usr/local/bin/cloudflared -V) installed for ${ARCH}" >> /build_date.info

# Clean cloudflared config.
mkdir -p /etc/cloudflared
rm -f /etc/cloudflared/config.yml

# Log unbound version.
echo "$(date "+%d.%m.%Y %T") Unbound $(unbound -V | head -1) installed for ${ARCH}" >> /build_date.info

# Clean up temporary files.
rm -rf /tmp/* /var/tmp/*

# Create the pihole-dot-doh service.
mkdir -p /etc/services.d/pihole-dot-doh

# Create run script for the service.
cat << 'EOF' > /etc/services.d/pihole-dot-doh/run
#!/bin/sh
# Copy default configs from /temp to /config if not already present.
cp -n /temp/stubby.yml /config/
cp -n /temp/cloudflared.yml /config/
cp -n /temp/unbound.conf /config/
cp -n /temp/forward-records.conf /config/
# Start unbound in the background.
echo "Starting unbound"
exec /usr/local/sbin/unbound -p -c /config/unbound.conf &
# Start stubby in the background.
echo "Starting stubby"
exec stubby -g -C /config/stubby.yml &
# Start cloudflared in the foreground.
echo "Starting cloudflared"
exec /usr/local/bin/cloudflared --config /config/cloudflared.yml
EOF

chmod 755 /etc/services.d/pihole-dot-doh/run

# Create finish script for the service.
cat << 'EOF' > /etc/services.d/pihole-dot-doh/finish
#!/bin/sh
echo "Stopping stubby"
killall -9 stubby
echo "Stopping cloudflared"
killall -9 cloudflared
echo "Stopping unbound"
killall -9 unbound
EOF

chmod 755 /etc/services.d/pihole-dot-doh/finish

# Create a oneshot for unbound configuration.
mkdir -p /etc/cont-init.d/
cp -n /temp/unbound.sh /etc/cont-init.d/unbound
chmod 755 /etc/cont-init.d/unbound
