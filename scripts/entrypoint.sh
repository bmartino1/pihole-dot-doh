#!/bin/sh
set -e

# Check for custom Cloudflared config in /config; if not present, copy default from /build
if [ ! -f /config/cloudflared.conf ]; then
  echo "Custom Cloudflared config not found in /config, copying default."
  cp /build/cloudflared.conf /config/cloudflared.conf
fi

# Check for custom Unbound config in /config; if not present, copy default from /build.
# Note: The file is now called unbound-pi-hole.conf for clarity.
if [ ! -f /config/unbound-pi-hole.conf ]; then
  echo "Custom Unbound config not found in /config, copying default."
  cp /build/unbound-pi-hole.conf /config/unbound-pi-hole.conf
fi

# Create symlink for Cloudflared config
if [ ! -L /etc/cloudflared/config.yml ]; then
  rm -f /etc/cloudflared/config.yml
  ln -s /config/cloudflared.conf /etc/cloudflared/config.yml
fi

# Create symlink for Unbound config per Pi-hole documentation, renamed for clarity.
if [ ! -L /etc/unbound/unbound.conf.d/unbound-pi-hole.conf ]; then
  rm -f /etc/unbound/unbound.conf.d/unbound-pi-hole.conf
  ln -s /config/unbound-pi-hole.conf /etc/unbound/unbound.conf.d/unbound-pi-hole.conf
fi

# Download Unbound root hints if not present (after unbound pi-hole root hints)
if [ ! -f /var/lib/unbound/root.hints ]; then
  echo "Downloading Unbound root hints..."
  wget https://www.internic.net/domain/named.root -qO- > /var/lib/unbound/root.hints
fi

# Start required services
echo "Starting services..."
lighttpd -D &
php-fpm7 &
unbound -d &

# Source the Cloudflared config to load CLOUDFLARED_OPTS variable
. /config/cloudflared.conf
cloudflared \$CLOUDFLARED_OPTS &

# Start Pi-hole FTL in the foreground to keep the container running
pihole-FTL -f
