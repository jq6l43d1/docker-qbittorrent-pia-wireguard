#!/bin/bash
# Install the pia-stack-restarter systemd path+service on the docker host
# (e.g. the LXC running these stacks). Run as root.

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)

install -d -m 0755 /var/lib/pia-stacks
chmod 1777 /var/lib/pia-stacks  # sticky world-writable: containers (as root inside) write here

install -m 0755 "$SCRIPT_DIR/pia-stack-restarter.sh"      /usr/local/sbin/pia-stack-restarter.sh
install -m 0644 "$SCRIPT_DIR/pia-stack-restarter.service" /etc/systemd/system/pia-stack-restarter.service
install -m 0644 "$SCRIPT_DIR/pia-stack-restarter.path"    /etc/systemd/system/pia-stack-restarter.path

systemctl daemon-reload
systemctl enable --now pia-stack-restarter.path

echo "Installed. Verify with:"
echo "  systemctl status pia-stack-restarter.path"
echo "  journalctl -u pia-stack-restarter -f"
echo "Manually trigger a restart of stack 'tv-01' with:"
echo "  touch /var/lib/pia-stacks/tv-01.restart"
