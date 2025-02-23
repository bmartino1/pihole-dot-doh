#!/usr/bin/env bash

# Configure unbound: download root hints if missing.
if [ ! -f /var/lib/unbound/root.hints ]; then
    mkdir -p /var/lib/unbound
    wget https://www.internic.net/domain/named.root -qO- | tee /var/lib/unbound/root.hints >/dev/null
fi

echo "$(date "+%d.%m.%Y %T") Unbound $(unbound -V | grep "Version") installed"

# Ensure unbound log file exists with proper permissions.
if [ ! -f /var/log/unbound/unbound.log ]; then
    mkdir -p /var/log/unbound
    touch /var/log/unbound/unbound.log
    chown -R unbound:unbound /var/log/unbound
fi

# Calculate available memory for cache sizes.
reserved=12582912
availableMemory=$((1024 * $( (grep MemAvailable /proc/meminfo || grep MemTotal /proc/meminfo) | sed 's/[^0-9]//g' ) ))
memoryLimit=$availableMemory
[ -r /sys/fs/cgroup/memory/memory.limit_in_bytes ] && memoryLimit=$(cat /sys/fs/cgroup/memory/memory.limit_in_bytes | sed 's/[^0-9]//g')
[[ ! -z $memoryLimit && $memoryLimit -gt 0 && $memoryLimit -lt $availableMemory ]] && availableMemory=$memoryLimit
if [ $availableMemory -le $((reserved * 2)) ]; then
    echo "Not enough memory" >&2
    exit 1
fi
availableMemory=$((availableMemory - reserved))
rr_cache_size=$(( availableMemory / 3 ))
msg_cache_size=$(( rr_cache_size / 2 ))
nproc=$(nproc)
export nproc
if [ "$nproc" -gt 1 ]; then
    threads=$(( nproc - 1 ))
    # Calculate base-2 log of the number of processors using perl.
    nproc_log=$(perl -e 'printf "%5.5f\n", log($ENV{nproc})/log(2);')
    rounded_nproc_log=$(printf '%.0f\n' "$nproc_log")
    # Set slabs to a power of 2 close to the thread count.
    slabs=$(( 2 ** rounded_nproc_log ))
else
    threads=1
    slabs=4
fi

# If no custom unbound config is found, update the default template with calculated values.
if [ ! -f /config/unbound.conf ]; then
    sed \
        -e "s/@MSG_CACHE_SIZE@/${msg_cache_size}/" \
        -e "s/@RR_CACHE_SIZE@/${rr_cache_size}/" \
        -e "s/@THREADS@/${threads}/" \
        -e "s/@SLABS@/${slabs}/" \
        /temp/unbound.conf > /temp/unbound.conf.tmp && mv /temp/unbound.conf.tmp /temp/unbound.conf
fi

# Adjust IPv6 setting based on the IPv6 environment variable.
IPv6_lower=$(echo "$IPv6" | tr '[:upper:]' '[:lower:]')
if [ "$IPv6_lower" = "true" ]; then
    sed -i '/^\s*do-ip6:/ s/no/yes/' /temp/unbound.conf
    [ -f /config/unbound.conf ] && sed -i '/^\s*do-ip6:/ s/no/yes/' /config/unbound.conf
else
    sed -i '/^\s*do-ip6:/ s/yes/no/' /temp/unbound.conf
    [ -f /config/unbound.conf ] && sed -i '/^\s*do-ip6:/ s/yes/no/' /config/unbound.conf
fi
