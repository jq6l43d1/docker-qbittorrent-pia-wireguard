#!/usr/bin/with-contenv bash

echo "[qbit-auto-config] Starting qBittorrent auto-configuration..."

QBIT_CONF="/config/qBittorrent/qBittorrent.conf"
PORT_FILE="/pia-shared/port.dat"

# Wait for config directory to exist
mkdir -p /config/qBittorrent

# Wait for port file to be available (max 60 seconds)
WAIT_TIME=0
while [ ! -f "$PORT_FILE" ] && [ $WAIT_TIME -lt 60 ]; do
    echo "[qbit-auto-config] Waiting for PIA port forwarding... ($WAIT_TIME/60)"
    sleep 2
    WAIT_TIME=$((WAIT_TIME + 2))
done

# Read the forwarded port
if [ -f "$PORT_FILE" ]; then
    FORWARDED_PORT=$(cat "$PORT_FILE")
    echo "[qbit-auto-config] Found PIA forwarded port: $FORWARDED_PORT"

    # Wait for qBittorrent config to be created
    WAIT_TIME=0
    while [ ! -f "$QBIT_CONF" ] && [ $WAIT_TIME -lt 30 ]; do
        echo "[qbit-auto-config] Waiting for qBittorrent config file... ($WAIT_TIME/30)"
        sleep 2
        WAIT_TIME=$((WAIT_TIME + 2))
    done

    if [ -f "$QBIT_CONF" ]; then
        echo "[qbit-auto-config] Updating qBittorrent configuration..."

        # Update port in config
        sed -i "s/^Connection\\\\PortRangeMin=.*/Connection\\\\PortRangeMin=$FORWARDED_PORT/" "$QBIT_CONF"

        # Ensure VPN interface is set
        if ! grep -q "^Connection\\\\Interface=wg0" "$QBIT_CONF"; then
            echo "[qbit-auto-config] Setting network interface to wg0..."
            sed -i '/^\[Preferences\]/a Connection\\Interface=wg0\nConnection\\InterfaceName=wg0\nConnection\\InterfaceAddress=' "$QBIT_CONF"
        fi

        # Ensure UPnP is disabled
        sed -i "s/^Connection\\\\UPnP=.*/Connection\\\\UPnP=false/" "$QBIT_CONF"

        echo "[qbit-auto-config] Configuration updated successfully!"
        echo "[qbit-auto-config] - Port: $FORWARDED_PORT"
        echo "[qbit-auto-config] - Interface: wg0"
        echo "[qbit-auto-config] - UPnP: disabled"
    else
        echo "[qbit-auto-config] Warning: qBittorrent config file not found, will use defaults"
    fi
else
    echo "[qbit-auto-config] Warning: PIA port file not found, using default port 6881"
fi

echo "[qbit-auto-config] Auto-configuration complete!"
