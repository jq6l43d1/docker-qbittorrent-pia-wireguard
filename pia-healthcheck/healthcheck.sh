#!/bin/sh
# Healthcheck for the pia-wireguard container.
#
# Pings PIA's gateway through the tunnel. Reports unhealthy when the ping
# fails. After MAX_FAILS consecutive failures it kills PID 1 so docker's
# restart policy brings the container back up with a fresh PIA session;
# without this, an unhealthy tunnel can stay wedged indefinitely (the
# image runs with EXIT_ON_FATAL=0 and docker does not auto-restart on
# unhealthy state alone).

FAIL_FILE=/tmp/.wg-hc-fail
MAX_FAILS=5

if ping -c 1 -W 3 1.1.1.1 >/dev/null 2>&1; then
    rm -f "$FAIL_FILE"
    exit 0
fi

count=$(( $(cat "$FAIL_FILE" 2>/dev/null || echo 0) + 1 ))
echo "$count" > "$FAIL_FILE"

if [ "$count" -ge "$MAX_FAILS" ]; then
    echo "[wg-healthcheck] $count consecutive ping failures, killing PID 1 to trigger restart" >&2
    kill 1
fi

exit 1
