#!/usr/bin/with-contenv bash

echo "[qbit-auto-config] Starting qBittorrent auto-configuration..."

QBIT_CONF="/config/qBittorrent/qBittorrent.conf"
PORT_FILE="/pia-shared/port.dat"

# Validate WebUI password is set
if [ -z "$WEBUI_PASSWORD" ]; then
    echo "[qbit-auto-config] =========================================="
    echo "[qbit-auto-config] WARNING: WEBUI_PASSWORD is not set!"
    echo "[qbit-auto-config] qBittorrent will use default credentials."
    echo "[qbit-auto-config] Please set WEBUI_PASSWORD in your .env file"
    echo "[qbit-auto-config] =========================================="
fi

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

        # Update BitTorrent port in config
        sed -i "s/^Connection\\\\PortRangeMin=.*/Connection\\\\PortRangeMin=$FORWARDED_PORT/" "$QBIT_CONF"

        # Ensure VPN interface is set
        if ! grep -q "^Connection\\\\Interface=wg0" "$QBIT_CONF"; then
            echo "[qbit-auto-config] Setting network interface to wg0..."
            sed -i '/^\[Preferences\]/a Connection\\Interface=wg0\nConnection\\InterfaceName=wg0\nConnection\\InterfaceAddress=' "$QBIT_CONF"
        fi

        # Ensure UPnP is disabled
        sed -i "s/^Connection\\\\UPnP=.*/Connection\\\\UPnP=false/" "$QBIT_CONF"

        # Configure WebUI credentials if provided
        if [ -n "$WEBUI_USERNAME" ] && [ -n "$WEBUI_PASSWORD" ]; then
            echo "[qbit-auto-config] Configuring WebUI credentials..."

            # Generate password hash using Python (available in LinuxServer image)
            SALT=$(python3 -c "import os, base64; print(base64.b64encode(os.urandom(16)).decode())")
            PASS_HASH=$(python3 -c "
import hashlib, base64
password = '$WEBUI_PASSWORD'
salt = base64.b64decode('$SALT')
hash_obj = hashlib.pbkdf2_hmac('sha256', password.encode(), salt, 100000, 32)
print(base64.b64encode(hash_obj).decode())
")
            FULL_HASH="@ByteArray($SALT:$PASS_HASH)"

            # Update or add WebUI username
            if grep -q "^WebUI\\\\Username=" "$QBIT_CONF"; then
                sed -i "s/^WebUI\\\\\\\\Username=.*/WebUI\\\\\\\\Username=$WEBUI_USERNAME/" "$QBIT_CONF"
            else
                sed -i '/^\[Preferences\]/a WebUI\\Username='"$WEBUI_USERNAME" "$QBIT_CONF"
            fi

            # Update or add WebUI password
            if grep -q "^WebUI\\\\Password_PBKDF2=" "$QBIT_CONF"; then
                sed -i "s|^WebUI\\\\\\\\Password_PBKDF2=.*|WebUI\\\\\\\\Password_PBKDF2=\"$FULL_HASH\"|" "$QBIT_CONF"
            else
                sed -i '/^\[Preferences\]/a WebUI\\Password_PBKDF2="'"$FULL_HASH"'"' "$QBIT_CONF"
            fi

            # Ensure authentication is enabled
            if grep -q "^WebUI\\\\AuthSubnetWhitelistEnabled=" "$QBIT_CONF"; then
                sed -i "s/^WebUI\\\\\\\\AuthSubnetWhitelistEnabled=.*/WebUI\\\\\\\\AuthSubnetWhitelistEnabled=false/" "$QBIT_CONF"
            else
                sed -i '/^\[Preferences\]/a WebUI\\AuthSubnetWhitelistEnabled=false' "$QBIT_CONF"
            fi

            echo "[qbit-auto-config] - WebUI Username: $WEBUI_USERNAME"
            echo "[qbit-auto-config] - WebUI Password: ****** (configured)"
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
