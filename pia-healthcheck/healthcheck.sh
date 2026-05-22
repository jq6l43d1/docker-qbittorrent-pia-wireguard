#!/bin/sh
# Healthcheck for the pia-wireguard container.
#
# Pings 1.1.1.1 through the WireGuard tunnel. Reports unhealthy when the
# ping fails. After MAX_FAILS consecutive failures it asks the host to
# restart the whole stack by writing a sentinel file to a bind-mounted
# directory; a systemd path unit on the host (see
# scripts/pia-stack-restarter.{path,service,sh}) watches the directory and
# performs `docker stop qbt+firefox → restart pia → start qbt+firefox`.
#
# Why signal the host instead of `kill 1` here: Docker's restart policy
# only restarts this container, not the sibling qbittorrent/firefox
# containers that share its network namespace via `network_mode:
# container:`. Restarting only pia leaves those siblings stranded in a
# dead netns (still alive, only `lo` present) — the WebUI then can't be
# reached even though pia comes back healthy. Restarting the whole stack
# from outside avoids that.
#
# Fallback: if the sentinel directory isn't mounted (older stacks, or
# host watchdog not installed), fall back to the previous behavior of
# wiping cached PIA state and killing PID 1 so at least pia itself can
# self-heal. Stale state in /pia (PIA's anon volume) can perpetuate the
# wedge — wg-gen would keep re-using the cached auth token, addKey would
# keep succeeding, but PIA's WireGuard data plane would never respond to
# handshakes. Forcing a re-auth on the next cycle breaks out of that
# state.

FAIL_FILE=/tmp/.wg-hc-fail
SIGNAL_DIR=/host-signal
MAX_FAILS=5

if ping -c 1 -W 3 1.1.1.1 >/dev/null 2>&1; then
    rm -f "$FAIL_FILE"
    exit 0
fi

count=$(( $(cat "$FAIL_FILE" 2>/dev/null || echo 0) + 1 ))
echo "$count" > "$FAIL_FILE"

if [ "$count" -ge "$MAX_FAILS" ]; then
    instance="${INSTANCE_NAME:-unknown}"
    if [ -d "$SIGNAL_DIR" ] && [ "$instance" != "unknown" ]; then
        echo "[wg-healthcheck] $count consecutive ping failures, signaling host watchdog to restart stack '$instance'" >&2
        # Tokens are wiped by the host restarter before it starts pia, so
        # the next cycle still gets a fresh PIA auth.
        : > "$SIGNAL_DIR/$instance.restart"
        # Reset our counter so the next cycle gets a clean MAX_FAILS
        # window. The healthcheck will keep running during the restart;
        # without this it would re-signal every iteration.
        rm -f "$FAIL_FILE"
    else
        echo "[wg-healthcheck] $count consecutive ping failures, sentinel dir unavailable (instance=$instance) — falling back to kill PID 1" >&2
        rm -f /pia/.token /pia/portsig.json
        # Reset our own counter; /tmp survives the entrypoint's in-place
        # re-exec, so without this the counter would accumulate across
        # cycles and every subsequent failure would trip kill-1
        # immediately rather than after another five misses.
        rm -f "$FAIL_FILE"
        kill 1
    fi
fi

exit 1
