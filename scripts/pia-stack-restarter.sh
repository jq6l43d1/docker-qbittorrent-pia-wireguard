#!/bin/bash
# Host-side restarter for pia-qbittorrent-wireguard stacks.
#
# Triggered by pia-stack-restarter.path when a sentinel file appears in
# /var/lib/pia-stacks (written by the pia-wireguard container's
# healthcheck when it has decided the tunnel is wedged). For each
# sentinel, restarts the whole stack so qbittorrent (and firefox, if
# present) re-attach to pia-wireguard's fresh network namespace —
# `docker restart pia-wireguard-*` alone would orphan them in a dead
# netns because their `network_mode: container:pia-wireguard-*` link
# isn't re-resolved on the target's restart.
#
# Stale-PIA-token recovery: before restarting pia, wipe its anonymous
# /pia volume's cached auth token and port-forward signature, so the
# fresh container re-authenticates from scratch. This was the role of
# `rm -f /pia/.token /pia/portsig.json` inside the container under the
# old kill-1 mechanism; we do the equivalent here from outside.

set -u

SIGNAL_DIR=/var/lib/pia-stacks
LOG_TAG=pia-stack-restarter
PIA_SETTLE_SECS=8

log() { logger -t "$LOG_TAG" -- "$*"; echo "[$LOG_TAG] $*"; }

# Wipe stale PIA tokens by mounting the named volume on a throwaway
# container. The PIA wireguard image stores tokens in /pia (anonymous
# volume by default), so we look up its mount source from `docker
# inspect` and clear those files there.
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
    local stack=$1
    local pia=pia-wireguard-$stack qbt=qbittorrent-$stack ff=firefox-$stack

    if ! docker inspect "$pia" >/dev/null 2>&1; then
        log "no container named $pia, ignoring sentinel"
        return
    fi

    log "restarting stack '$stack'"

    # Stop sibling containers first so they release their netns reference
    # to the about-to-be-replaced pia container.
    for c in "$qbt" "$ff"; do
        docker inspect "$c" >/dev/null 2>&1 && docker stop "$c" >/dev/null 2>&1 && log "stopped $c"
    done

    wipe_pia_tokens "$stack"

    docker restart "$pia" >/dev/null && log "restarted $pia"

    sleep "$PIA_SETTLE_SECS"

    for c in "$qbt" "$ff"; do
        docker inspect "$c" >/dev/null 2>&1 && docker start "$c" >/dev/null 2>&1 && log "started $c"
    done

    log "stack '$stack' restart complete"
}

if [ ! -d "$SIGNAL_DIR" ]; then
    log "signal dir $SIGNAL_DIR missing, nothing to do"
    exit 0
fi

shopt -s nullglob
for sentinel in "$SIGNAL_DIR"/*.restart; do
    stack=$(basename "$sentinel" .restart)
    rm -f "$sentinel"
    restart_stack "$stack"
done
