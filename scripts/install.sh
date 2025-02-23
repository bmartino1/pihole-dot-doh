#!/bin/sh
set -eux

# 1) Architecture detection for Cloudflared installation.
ARCH=$(uname -m)
case "$ARCH" in
    aarch64|arm64)
        CF_PACKAGE="cloudflared-linux-arm64.apk"
        ;;
    arm*)
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

# 2) Install Cloudflared at runtime.
echo "Installing Cloudflared for $ARCH..."
wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/${CF_PACKAGE} -O /tmp/cloudflared.apk
apk add --allow-untrusted /tmp/cloudflared.apk || true
rm -f /tmp/cloudflared.apk

# Log Cloudflared version.
echo "$(date '+%d.%m.%Y %T') Cloudflared: $(cloudflared -v) for ${ARCH}" >> /build_date.info

# 3) Clean up any old configurations.
mkdir -p /etc/stubby
rm -f /etc/stubby/stubby.yml
mkdir -p /etc/cloudflared
rm -f /etc/cloudflared/config.yml

# 4) Log Unbound version.
echo "$(date '+%d.%m.%Y %T') Unbound $(unbound -V | head -1) installed for ${ARCH}" >> /build_date.info

# 5) Create the pihole-dot-doh service for Unbound, Stubby, and Cloudflared.
mkdir -p /etc/services.d/pihole-dot-doh
cat << 'EOF' > /etc/services.d/pihole-dot-doh/run
#!/bin/sh
# Copy default configs if not present in /config.
cp -n /temp/stubby.yml /config/
cp -n /temp/cloudflared.yml /config/
cp -n /temp/unbound.conf /config/
cp -n /temp/forward-records.conf /config/

echo "Starting unbound..."
/usr/local/sbin/unbound -p -c /config/unbound.conf &

echo "Starting stubby..."
stubby -g -C /config/stubby.yml &

echo "Starting cloudflared..."
exec cloudflared --config /config/cloudflared.yml
EOF
chmod 755 /etc/services.d/pihole-dot-doh/run

# 6) Create a finish script for pihole-dot-doh.
cat << 'EOF' > /etc/services.d/pihole-dot-doh/finish
#!/bin/sh
echo "Stopping stubby..."
killall -9 stubby || true
echo "Stopping cloudflared..."
killall -9 cloudflared || true
echo "Stopping unbound..."
killall -9 unbound || true
EOF
chmod 755 /etc/services.d/pihole-dot-doh/finish

# 7) If an unbound.sh script exists (for memory calculation, root hints, etc.), copy it.
if [ -f /temp/unbound.sh ]; then
  cp -n /temp/unbound.sh /etc/cont-init.d/unbound
  chmod 755 /etc/cont-init.d/unbound
fi

# 8) Cleanup temporary files.
rm -rf /tmp/* /var/tmp/*
