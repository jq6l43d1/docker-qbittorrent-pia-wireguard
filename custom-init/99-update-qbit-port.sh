#!/usr/bin/with-contenv bash

echo "[qbit-auto-config] Starting qBittorrent auto-configuration..."

QBIT_CONF="/config/qBittorrent/qBittorrent.conf"
PORT_FILE="/pia-shared/port.dat"

# Wait for config directory to exist
mkdir -p /config/qBittorrent

# Wait for port file to be available and fresh (max 90 seconds)
WAIT_TIME=0
MAX_WAIT=90
FILE_AGE=999

echo "[qbit-auto-config] Waiting for PIA to establish port forwarding..."

while [ $WAIT_TIME -lt $MAX_WAIT ]; do
    if [ -f "$PORT_FILE" ]; then
        # Check if file was modified in the last 60 seconds (fresh)
        FILE_AGE=$(( $(date +%s) - $(stat -c %Y "$PORT_FILE" 2>/dev/null || echo 0) ))

        if [ $FILE_AGE -lt 60 ]; then
            echo "[qbit-auto-config] Found fresh port file (${FILE_AGE}s old)"
            break
        else
            echo "[qbit-auto-config] Port file exists but is stale (${FILE_AGE}s old), waiting for update... ($WAIT_TIME/$MAX_WAIT)"
        fi
    else
        echo "[qbit-auto-config] Waiting for port file... ($WAIT_TIME/$MAX_WAIT)"
    fi

    sleep 3
    WAIT_TIME=$((WAIT_TIME + 3))
done

# Read the forwarded port
if [ -f "$PORT_FILE" ]; then
    FORWARDED_PORT=$(cat "$PORT_FILE")

    # Validate port number
    if [ -z "$FORWARDED_PORT" ] || ! [[ "$FORWARDED_PORT" =~ ^[0-9]+$ ]]; then
        echo "[qbit-auto-config] WARNING: Invalid or empty port in file, using default 6881"
        FORWARDED_PORT=6881
    else
        echo "[qbit-auto-config] Found PIA forwarded port: $FORWARDED_PORT (file age: ${FILE_AGE}s)"
    fi

    # Wait for qBittorrent config to be created
    WAIT_TIME=0
    while [ ! -f "$QBIT_CONF" ] && [ $WAIT_TIME -lt 30 ]; do
        echo "[qbit-auto-config] Waiting for qBittorrent config file... ($WAIT_TIME/30)"
        sleep 2
        WAIT_TIME=$((WAIT_TIME + 2))
    done

    if [ -f "$QBIT_CONF" ]; then
        echo "[qbit-auto-config] Updating qBittorrent configuration..."

        # Update Session\Port (the key qBittorrent v5+ actually uses)
        if grep -q "^Session\\\\Port=" "$QBIT_CONF"; then
            sed -i "s/^Session\\\\Port=.*/Session\\\\Port=$FORWARDED_PORT/" "$QBIT_CONF"
        else
            sed -i '/^\[BitTorrent\]/a Session\\Port='"$FORWARDED_PORT" "$QBIT_CONF"
        fi

        # Also update legacy Connection\PortRangeMin key
        if grep -q "^Connection\\\\PortRangeMin=" "$QBIT_CONF"; then
            sed -i "s/^Connection\\\\PortRangeMin=.*/Connection\\\\PortRangeMin=$FORWARDED_PORT/" "$QBIT_CONF"
        fi

        # Ensure VPN interface is set
        if ! grep -q "^Connection\\\\Interface=wg0" "$QBIT_CONF"; then
            echo "[qbit-auto-config] Setting network interface to wg0..."
            sed -i '/^\[Preferences\]/a Connection\\Interface=wg0\nConnection\\InterfaceName=wg0\nConnection\\InterfaceAddress=' "$QBIT_CONF"
        fi

        # Ensure UPnP is disabled
        sed -i "s/^Connection\\\\UPnP=.*/Connection\\\\UPnP=false/" "$QBIT_CONF"

        # Configure WebUI port if provided
        if [ -n "$WEBUI_PORT" ]; then
            echo "[qbit-auto-config] Configuring WebUI port to $WEBUI_PORT..."
            if grep -q "^WebUI\\\\Port=" "$QBIT_CONF"; then
                sed -i "s/^WebUI\\\\\\\\Port=.*/WebUI\\\\\\\\Port=$WEBUI_PORT/" "$QBIT_CONF"
            else
                sed -i '/^\[Preferences\]/a WebUI\\Port='"$WEBUI_PORT" "$QBIT_CONF"
            fi
        fi

        echo "[qbit-auto-config] Configuration updated successfully!"
        echo "[qbit-auto-config] - BitTorrent Port: $FORWARDED_PORT"
        echo "[qbit-auto-config] - WebUI Port: ${WEBUI_PORT:-8080}"
        echo "[qbit-auto-config] - Interface: wg0"
        echo "[qbit-auto-config] - UPnP: disabled"
    else
        echo "[qbit-auto-config] Warning: qBittorrent config file not found, will use defaults"
    fi
else
    echo "[qbit-auto-config] Warning: PIA port file not found, using default port 6881"
fi

echo "[qbit-auto-config] Auto-configuration complete!"
