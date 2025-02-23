#!/usr/bin/env bash
# Minimal rewrite of Pi-hole's basic-install.sh for Alpine Linux
# Removes OS/distro checks, SELinux, systemd, meta-package building, interactive dialogs, etc.
# Installs Pi-hole by cloning repos, setting up config, and starting services in the foreground.

set -eux

# 1) Root check
if [ "$(id -u)" -ne 0 ]; then
  echo "Error: This installer must be run as root." >&2
  exit 1
fi

# 2) Basic environment
export PATH="$PATH:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# 3) Create pihole user/group if missing
if ! id -u pihole &>/dev/null; then
  addgroup -S pihole || true
  adduser -S -G pihole pihole || true
fi

# 4) Create needed directories
mkdir -p /etc/pihole /var/www/html /var/log/pihole
rm -rf /etc/.pihole /var/www/html/admin  # always clone fresh

# 5) Clone Pi-hole core + web repos
echo "Cloning Pi-hole core repo..."
git clone --depth=1 https://github.com/pi-hole/pi-hole.git /etc/.pihole

echo "Cloning Pi-hole web interface..."
git clone --depth=1 https://github.com/pi-hole/web.git /var/www/html/admin

# 6) If no /etc/pihole/setupVars.conf, create minimal default
if [ ! -f /etc/pihole/setupVars.conf ]; then
  echo "Creating minimal /etc/pihole/setupVars.conf..."
  cat <<EOF > /etc/pihole/setupVars.conf
WEBPASSWORD=
EOF
fi

# 7) Generate admin password if missing
if ! grep -q '^WEBPASSWORD=' /etc/pihole/setupVars.conf || \
   [ "$(grep '^WEBPASSWORD=' /etc/pihole/setupVars.conf | cut -d'=' -f2)" = "" ]; then
  PW="$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 8)"
  echo "WEBPASSWORD=$PW" >> /etc/pihole/setupVars.conf
  echo "Pi-hole admin password: $PW"
fi

# 8) Minimal lighttpd config
cat <<EOF > /etc/lighttpd/lighttpd.conf
server.document-root = "/var/www/html"
server.errorlog      = "/var/log/lighttpd/error.log"
server.pid-file      = "/var/run/lighttpd.pid"
server.port          = 80
EOF

# 9) Check for pihole-FTL binary
if [ ! -x /usr/bin/pihole-FTL ]; then
  echo "Error: pihole-FTL not found in /usr/bin. Aborting." >&2
  exit 1
fi

# 10) (Optional) Copy additional configs from /temp
if [ -f /temp/unbound.conf ]; then
  mkdir -p /etc/unbound/unbound.conf.d
  cp /temp/unbound.conf /etc/unbound/unbound.conf.d/pi-hole.conf
fi
if [ -f /temp/pihole.toml ]; then
  cp /temp/pihole.toml /etc/pihole/pihole.toml
fi

# 11) Start services in foreground
echo "Starting Lighttpd, PHP-FPM, and Pi-hole FTL..."
lighttpd -D &        # run Lighttpd in background
php-fpm8 &           # run PHP-FPM in background
exec pihole-FTL -f   # run pihole-FTL in the foreground
