#!/bin/sh
# Healthcheck for the pia-wireguard container.
#
# Pings 1.1.1.1 through the WireGuard tunnel. Reports unhealthy when the
# ping fails. After MAX_FAILS consecutive failures it wipes the cached
# PIA auth/PF tokens and kills PID 1 so the entrypoint re-execs with a
# fresh PIA session. Without the wipe, stale state in /pia (PIA's anon
# volume) can itself perpetuate the wedge — wg-gen would keep re-using
# the same cached auth token, addKey would keep succeeding, but PIA's
# WireGuard data plane would never respond to handshakes. Forcing a
# re-auth on every kill-1 breaks out of that state. (Docker does NOT
# auto-restart on unhealthy alone, and the image runs with
# EXIT_ON_FATAL=0, so the script is the actual self-healing mechanism.)

FAIL_FILE=/tmp/.wg-hc-fail
MAX_FAILS=5

if ping -c 1 -W 3 1.1.1.1 >/dev/null 2>&1; then
    rm -f "$FAIL_FILE"
    exit 0
fi

count=$(( $(cat "$FAIL_FILE" 2>/dev/null || echo 0) + 1 ))
echo "$count" > "$FAIL_FILE"

if [ "$count" -ge "$MAX_FAILS" ]; then
    echo "[wg-healthcheck] $count consecutive ping failures, wiping cached PIA state and killing PID 1 to trigger restart" >&2
    # Force wg-gen to re-auth and re-fetch a PF signature on the next
    # cycle. Stale tokens in /pia can themselves be the wedge cause.
    rm -f /pia/.token /pia/portsig.json
    # Reset our own counter so the next cycle gets a clean MAX_FAILS
    # window before kill-1 fires again. /tmp survives the entrypoint's
    # in-place re-exec, so without this the counter would accumulate
    # across cycles and every subsequent failure would trip kill-1
    # immediately rather than after another five misses.
    rm -f "$FAIL_FILE"
    kill 1
fi

exit 1
