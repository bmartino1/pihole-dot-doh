#!/bin/sh
set -eux

# Custom Alpine Pi-hole Installer
# This script installs and configures Pi-hole on Alpine Linux.
# It clones (or updates) the Pi-hole core repository and the web interface,
# sets up default configuration, and then starts Lighttpd, PHP-FPM, and pihole-FTL.
#
# NOTE: This installer is simplified for Alpine and does not cover every feature
# of the official installer. You can expand or modify it as needed.

# Ensure the script is run as root.
if [ "$(id -u)" -ne 0 ]; then
  echo "Error: This installer must be run as root." >&2
  exit 1
fi

# Append standard system directories to PATH
export PATH="$PATH:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# Create necessary directories.
mkdir -p /etc/pihole /opt/pihole /var/www/html/admin /var/log/pihole

# Clone or update the Pi-hole core repository.
if [ ! -d /etc/.pihole ]; then
  echo "Cloning Pi-hole core repository..."
  git clone --depth 1 https://github.com/pi-hole/pi-hole.git /etc/.pihole
else
  echo "Updating Pi-hole core repository..."
  cd /etc/.pihole && git pull --rebase
fi

# Clone or update the Pi-hole web interface.
if [ ! -d /var/www/html/admin ]; then
  echo "Cloning Pi-hole web interface..."
  git clone --depth 1 https://github.com/pi-hole/web.git /var/www/html/admin
else
  echo "Updating Pi-hole web interface..."
  cd /var/www/html/admin && git pull --rebase
fi

# Install default configuration if not already present.
if [ ! -f /etc/pihole/setupVars.conf ]; then
  echo "Installing default configuration..."
  if [ -f /etc/.pihole/automated\ install/setupVars.conf.example ]; then
    cp /etc/.pihole/automated\ install/setupVars.conf.example /etc/pihole/setupVars.conf
  else
    cat > /etc/pihole/setupVars.conf <<EOF
WEBPASSWORD=
EOF
  fi
fi

# If no admin password is set, generate one and record it.
if ! grep -q "^WEBPASSWORD=" /etc/pihole/setupVars.conf || \
   [ "$(grep '^WEBPASSWORD=' /etc/pihole/setupVars.conf | cut -d'=' -f2)" = "" ]; then
  PASSWORD=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 8)
  echo "WEBPASSWORD=${PASSWORD}" >> /etc/pihole/setupVars.conf
  echo "Admin password set to: ${PASSWORD}"
fi

# Configure Lighttpd with a minimal configuration.
cat > /etc/lighttpd/lighttpd.conf <<EOF
server.document-root = "/var/www/html"
server.errorlog = "/var/log/lighttpd/error.log"
server.pid-file = "/var/run/lighttpd.pid"
server.port = 80
EOF

# Warn if PHP-FPM configuration is missing.
if [ ! -f /etc/php8/php-fpm.conf ] && [ ! -f /etc/php83/php-fpm.conf ]; then
  echo "Warning: PHP-FPM configuration file not found; please verify your PHP-FPM setup."
fi

# Ensure pihole-FTL is present.
if [ ! -x /usr/bin/pihole-FTL ]; then
  echo "Error: pihole-FTL binary not found in /usr/bin. Aborting installation." >&2
  exit 1
fi

# Optionally, copy additional default configuration files from /temp if provided.
# For example, if you have a default unbound.conf or pihole.toml in /temp, copy them:
if [ -f /temp/unbound.conf ]; then
  cp /temp/unbound.conf /etc/unbound/unbound.conf.d/10-pihole.conf
fi
if [ -f /temp/pihole.toml ]; then
  cp /temp/pihole.toml /etc/pihole/pihole.toml
fi

# Final message and starting services.
echo "Pi-hole installation on Alpine is complete. Starting services..."
# Start Lighttpd (web server) in background.
lighttpd -D &
# Start PHP-FPM in background.
php-fpm8 &
# Finally, start Pi-hole FTL in the foreground.
exec pihole-FTL -f
