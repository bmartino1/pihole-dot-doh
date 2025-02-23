#!/usr/bin/env bash
# scripts/pihole-run.sh

# Start Lighttpd (web interface) in the background
echo "Starting Lighttpd..."
lighttpd -D &

# Start PHP-FPM in the background
echo "Starting PHP-FPM..."
php-fpm7 &

# Finally, start pihole-FTL in the foreground
echo "Starting Pi-hole FTL..."
exec pihole-FTL -f
