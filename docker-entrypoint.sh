#!/bin/sh
set -eu

# Forward common Squid logs to container logs.
tail -F /var/log/squid/access.log 2>/dev/null &
tail -F /var/log/squid/error.log 2>/dev/null &
tail -F /var/log/squid/store.log 2>/dev/null &
tail -F /var/log/squid/cache.log 2>/dev/null &

# Create missing cache directories and exit using the same config file
# passed by default CMD/manifest.
/usr/sbin/squid -Nz -f /etc/squid/squid.conf

# Run Squid with CMD/command arguments.
exec /usr/sbin/squid "$@"
