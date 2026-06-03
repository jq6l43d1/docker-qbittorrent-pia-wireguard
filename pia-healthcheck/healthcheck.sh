#!/bin/sh
# Healthcheck for the pia-wireguard container.
#
# Pings 1.1.1.1 through the WireGuard tunnel. Reports unhealthy when the
# ping fails. When it concludes the tunnel is genuinely WEDGED it asks the
# host to restart the whole stack by writing a sentinel file to a
# bind-mounted directory; a systemd path unit on the host (see
# scripts/pia-stack-restarter.{path,service,sh}) watches the directory and
# performs `docker stop qbt+firefox -> restart pia -> start qbt+firefox`.
#
# Why signal the host instead of `kill 1` here: Docker's restart policy
# only restarts this container, not the sibling qbittorrent/firefox
# containers that share its network namespace via `network_mode:
# container:`. Restarting only pia leaves those siblings stranded in a
# dead netns (still alive, only `lo` present) -- the WebUI then can't be
# reached even though pia comes back healthy. Restarting the whole stack
# from outside avoids that.
#
# Fallback: if the sentinel directory isn't mounted (older stacks, or
# host watchdog not installed), fall back to the previous behavior of
# wiping cached PIA state and killing PID 1 so at least pia itself can
# self-heal.
#
# -----------------------------------------------------------------------
# WEDGE DETECTION (the important part -- see the 2026-06-03 incident).
#
# A naive "N consecutive ping failures -> signal" loop self-destructs:
#
#   1. Docker probes every StartInterval (1s) during start_period, so a
#      freshly (re)started tunnel racks up N failures in N seconds -- long
#      before WireGuard has finished handshaking -- and signals a restart.
#      The restart then triggers the next restart. Loop.
#   2. A single dropped ping on a flaky upstream WAN (Starlink) is NOT a
#      wedged tunnel, but a count-based check treats it the same.
#
# This version fixes both:
#   * STARTUP GRACE: never count or signal until this container's PID 1 has
#     been alive >= STARTUP_GRACE. Mirrors compose `start_period`, but for
#     our own signalling -- which Docker's start_period does NOT cover.
#   * HANDSHAKE GATE: only treat a ping failure as a possible wedge when the
#     WireGuard handshake has also gone stale. A fresh handshake + lost ping
#     is an upstream blip that self-recovers; don't restart for it.
#   * TIME-BASED THRESHOLD: signal only after the bad state persists for
#     WEDGE_SECS of wall-clock, so the probe cadence (StartInterval vs
#     Interval) is irrelevant.
# -----------------------------------------------------------------------

FAIL_FILE=/tmp/.wg-hc-fail      # epoch of the first failure in the current bad streak
SIGNAL_DIR=/host-signal
WG_IF=wg0

STARTUP_GRACE=${HC_STARTUP_GRACE:-90}        # s; suppress all signalling below this container age
WEDGE_SECS=${HC_WEDGE_SECS:-180}             # s; tunnel must stay bad this long before we call it wedged
HANDSHAKE_STALE=${HC_HANDSHAKE_STALE:-180}   # s; handshake older than this == PIA data plane likely dead

now=$(date +%s)

ping_ok() { ping -c 1 -W 3 1.1.1.1 >/dev/null 2>&1; }

# --- data-plane test ------------------------------------------------------
if ping_ok; then
    rm -f "$FAIL_FILE"
    exit 0
fi

# --- container-uptime (startup) gate --------------------------------------
# /tmp survives `docker restart`, so a stale fail-timestamp from a previous
# container life could otherwise trip an instant signal once grace passes.
# Computing PID 1's age and clearing FAIL_FILE during the grace window kills
# both problems: a (re)started tunnel is never signalled while coming up,
# and the wedge clock always starts fresh afterwards.
start_ticks=$(awk '{print $22}' /proc/1/stat 2>/dev/null)
case "$start_ticks" in ''|*[!0-9]*) start_ticks=0;; esac
if [ "$start_ticks" = 0 ]; then
    # Can't determine our own age -> fail safe by treating as "still starting".
    exit 1
fi
hz=$(getconf CLK_TCK 2>/dev/null || echo 100)
host_uptime=$(awk '{print $1}' /proc/uptime 2>/dev/null || echo 0)
pid1_uptime=$(awk -v u="$host_uptime" -v s="$start_ticks" -v hz="$hz" 'BEGIN{printf "%d", u - s/hz}')

if [ "$pid1_uptime" -lt "$STARTUP_GRACE" ]; then
    rm -f "$FAIL_FILE"   # keep the wedge clock from inheriting a previous life's timestamp
    exit 1
fi

# --- handshake gate: wedge vs. transient WAN blip -------------------------
# A wedged PIA tunnel stops refreshing its WireGuard handshake; a momentary
# upstream packet-loss blip does not. Only the former warrants a disruptive
# stack restart.
last_hs=$(wg show "$WG_IF" latest-handshakes 2>/dev/null | awk 'NR==1{print $2}')
case "$last_hs" in ''|*[!0-9]*) last_hs=0;; esac
hs_age=$(( now - last_hs ))

if [ "$last_hs" -ne 0 ] && [ "$hs_age" -lt "$HANDSHAKE_STALE" ]; then
    # Handshake is fresh: tunnel is up at the crypto layer. Treat the lost
    # ping as a transient blip -- reset the wedge clock and just report
    # unhealthy for this probe.
    rm -f "$FAIL_FILE"
    exit 1
fi

# --- wedge clock: require WEDGE_SECS of continuous bad state ---------------
first=$(cat "$FAIL_FILE" 2>/dev/null)
case "$first" in ''|*[!0-9]*) first=$now; echo "$first" > "$FAIL_FILE";; esac
bad_for=$(( now - first ))

if [ "$bad_for" -ge "$WEDGE_SECS" ]; then
    instance="${INSTANCE_NAME:-unknown}"
    if [ -d "$SIGNAL_DIR" ] && [ "$instance" != "unknown" ]; then
        echo "[wg-healthcheck] tunnel wedged ${bad_for}s (handshake age ${hs_age}s), signaling host watchdog to restart stack '$instance'" >&2
        # The host restarter decides whether to wipe PIA tokens (it escalates
        # to a token wipe only after repeated restarts), so we don't here.
        : > "$SIGNAL_DIR/$instance.restart"
        # Reset our clock so we don't re-signal every probe during the restart.
        rm -f "$FAIL_FILE"
    else
        echo "[wg-healthcheck] tunnel wedged ${bad_for}s, sentinel dir unavailable (instance=$instance) -- falling back to kill PID 1" >&2
        rm -f /pia/.token /pia/portsig.json
        rm -f "$FAIL_FILE"
        kill 1
    fi
fi

exit 1
