#!/bin/bash
# Host-side restarter for pia-qbittorrent-wireguard stacks.
#
# Triggered by pia-stack-restarter.path when a sentinel file appears in
# /var/lib/pia-stacks (written by the pia-wireguard container's healthcheck
# when it has decided the tunnel is wedged). For each sentinel, restarts the
# whole stack so qbittorrent (and firefox, if present) re-attach to
# pia-wireguard's fresh network namespace -- `docker restart pia-wireguard-*`
# alone would orphan them in a dead netns because their `network_mode:
# container:pia-wireguard-*` link isn't re-resolved on the target's restart.
#
# Loop protection (see the 2026-06-03 incident, where this restarter logged
# ~30k restarts in 24h):
#   * COOLDOWN   -- never restart the same stack more than once per
#                   COOLDOWN_SECS, so a stack that keeps signalling is
#                   throttled instead of hammered.
#   * TOKEN WIPE is ESCALATED, not unconditional -- a fresh PIA re-auth on
#     every restart is what trips PIA's `too_many_attempts` rate limit and
#     turns a transient wobble into a permanent spiral. We only wipe the
#     cached /pia token after WIPE_AFTER consecutive restarts.
#   * CIRCUIT BREAKER -- if a stack needs > BREAKER_MAX restarts within
#     BREAKER_WINDOW_SECS it is not self-healing; pause restarts for
#     BREAKER_COOLDOWN_SECS and drop a `<stack>.breaker` breadcrumb for
#     monitoring/alerting instead of restarting forever.
#   * flock per stack so overlapping path-unit triggers can't run concurrent
#     restarts of the same stack.
#
# State lives in STATE_DIR, which is deliberately NOT the watched SIGNAL_DIR
# (the .path unit triggers on any content under SIGNAL_DIR).

set -u

SIGNAL_DIR=/var/lib/pia-stacks
STATE_DIR=/var/lib/pia-stack-restarter
LOG_TAG=pia-stack-restarter
PIA_SETTLE_SECS=8

# --- loop-protection tunables ---------------------------------------------
COOLDOWN_SECS=${COOLDOWN_SECS:-120}                 # min seconds between restarts of the same stack
WIPE_AFTER=${WIPE_AFTER:-3}                         # wipe PIA token only from this restart-in-window onward
BREAKER_MAX=${BREAKER_MAX:-6}                       # restarts within the window before the breaker trips
BREAKER_WINDOW_SECS=${BREAKER_WINDOW_SECS:-1800}    # rolling window for counting restarts
BREAKER_COOLDOWN_SECS=${BREAKER_COOLDOWN_SECS:-1800} # how long restarts are paused once the breaker trips
HEAL_RESET_SECS=${HEAL_RESET_SECS:-600}             # quiet period after which a stack is considered healed

log() { logger -t "$LOG_TAG" -- "$*"; echo "[$LOG_TAG] $*"; }

# Wipe stale PIA tokens on the pia container's anonymous /pia volume so the
# fresh container re-authenticates from scratch.
wipe_pia_tokens() {
    local stack=$1 pia=pia-wireguard-$stack
    local pia_mount
    pia_mount=$(docker inspect "$pia" -f '{{range .Mounts}}{{if eq .Destination "/pia"}}{{.Source}}{{end}}{{end}}' 2>/dev/null)
    if [ -n "$pia_mount" ] && [ -d "$pia_mount" ]; then
        rm -f "$pia_mount/.token" "$pia_mount/portsig.json"
        log "wiped stale PIA tokens at $pia_mount"
    else
        log "could not locate /pia mount for $pia, skipping token wipe"
    fi
}

restart_stack() {
    local stack=$1 wipe=$2
    local pia=pia-wireguard-$stack qbt=qbittorrent-$stack ff=firefox-$stack

    if ! docker inspect "$pia" >/dev/null 2>&1; then
        log "no container named $pia, ignoring sentinel"
        return
    fi

    log "restarting stack '$stack' (wipe_tokens=$wipe)"

    # Stop sibling containers first so they release their netns reference
    # to the about-to-be-replaced pia container.
    for c in "$qbt" "$ff"; do
        docker inspect "$c" >/dev/null 2>&1 && docker stop "$c" >/dev/null 2>&1 && log "stopped $c"
    done

    [ "$wipe" = yes ] && wipe_pia_tokens "$stack"

    docker restart "$pia" >/dev/null && log "restarted $pia"

    sleep "$PIA_SETTLE_SECS"

    for c in "$qbt" "$ff"; do
        docker inspect "$c" >/dev/null 2>&1 && docker start "$c" >/dev/null 2>&1 && log "started $c"
    done

    log "stack '$stack' restart complete"
}

# State file format: "<last_epoch> <count_in_window> <window_start_epoch> <breaker_until_epoch>"
g_last=0 g_count=0 g_win=0 g_until=0
read_state() {
    local f="$STATE_DIR/$1.state"
    g_last=0 g_count=0 g_win=0 g_until=0
    [ -f "$f" ] && read -r g_last g_count g_win g_until < "$f" 2>/dev/null
    case "$g_last"  in ''|*[!0-9]*) g_last=0;;  esac
    case "$g_count" in ''|*[!0-9]*) g_count=0;; esac
    case "$g_win"   in ''|*[!0-9]*) g_win=0;;   esac
    case "$g_until" in ''|*[!0-9]*) g_until=0;; esac
}
write_state() { echo "$1 $2 $3 $4" > "$STATE_DIR/$5.state"; }

# Decide whether to restart this stack, applying cooldown + circuit breaker,
# then (if cleared) perform the restart with escalated token-wipe.
maybe_restart() {
    local stack=$1 now
    now=$(date +%s)
    read_state "$stack"

    # Breaker currently active -> refuse, leave a breadcrumb.
    if [ "$g_until" -gt "$now" ]; then
        log "stack '$stack' circuit breaker active for $((g_until - now))s more; skipping (investigate $STATE_DIR/$stack.breaker)"
        return
    fi

    # Long quiet period or expired window -> consider the stack healed and
    # reset the rolling counter.
    if { [ "$g_last" -ne 0 ] && [ $((now - g_last)) -ge "$HEAL_RESET_SECS" ]; } \
       || [ "$g_win" -eq 0 ] || [ $((now - g_win)) -ge "$BREAKER_WINDOW_SECS" ]; then
        g_count=0
        g_win=$now
        rm -f "$STATE_DIR/$stack.breaker"
    fi

    # Cooldown: too soon since the last restart -> defer (the healthcheck
    # will re-signal if it's still wedged after the cooldown).
    if [ "$g_last" -ne 0 ] && [ $((now - g_last)) -lt "$COOLDOWN_SECS" ]; then
        log "stack '$stack' restarted $((now - g_last))s ago (< cooldown ${COOLDOWN_SECS}s); skipping"
        return
    fi

    g_count=$((g_count + 1))

    # Circuit breaker: too many restarts in the window -> pause and alert.
    if [ "$g_count" -gt "$BREAKER_MAX" ]; then
        g_until=$((now + BREAKER_COOLDOWN_SECS))
        write_state "$g_last" 0 "$now" "$g_until" "$stack"
        log "CIRCUIT BREAKER TRIPPED for stack '$stack': > ${BREAKER_MAX} restarts in ${BREAKER_WINDOW_SECS}s. Pausing restarts ${BREAKER_COOLDOWN_SECS}s -- this stack is not self-healing, investigate."
        : > "$STATE_DIR/$stack.breaker"
        return
    fi

    local wipe=no
    [ "$g_count" -ge "$WIPE_AFTER" ] && wipe=yes

    write_state "$now" "$g_count" "$g_win" "$g_until" "$stack"
    log "stack '$stack': restart attempt $g_count/${BREAKER_MAX} in window"
    restart_stack "$stack" "$wipe"
}

mkdir -p "$STATE_DIR"

if [ ! -d "$SIGNAL_DIR" ]; then
    log "signal dir $SIGNAL_DIR missing, nothing to do"
    exit 0
fi

shopt -s nullglob
for sentinel in "$SIGNAL_DIR"/*.restart; do
    stack=$(basename "$sentinel" .restart)
    rm -f "$sentinel"
    # Per-stack lock: overlapping .path triggers must not run concurrent
    # restarts of the same stack.
    (
        flock -n 9 || { log "another restarter holds the lock for '$stack', skipping"; exit 0; }
        maybe_restart "$stack"
    ) 9>"$STATE_DIR/$stack.lock"
done
