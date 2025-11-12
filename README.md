# qBittorrent + PIA VPN with Automatic Port Forwarding

Fully automated Docker setup for qBittorrent with Private Internet Access (PIA) VPN using WireGuard. Zero manual configuration required.

## Features

✅ **Automatic VPN binding** - qBittorrent automatically binds to `wg0` interface
✅ **Auto port forwarding** - Dynamically reads and configures PIA's forwarded port
✅ **UPnP disabled** - Prevents accidental IP leaks
✅ **Pre-configured settings** - Optimized for VPN usage out of the box
✅ **Persistent configuration** - Settings survive container restarts
✅ **No hardcoded ports** - Handles PIA's dynamic port changes automatically
✅ **Multi-instance support** - Run multiple instances on the same system with different VPN locations
✅ **Configurable WebUI credentials** - Set your own username and password via environment variables

## Quick Start

### Prerequisites

- Docker and Docker Compose installed
- Active PIA VPN subscription
- PIA username and password

### Deployment

1. Clone this repository:
```bash
git clone https://github.com/jq6l43d1/docker-qbittorrent-pia-wireguard.git
cd docker-qbittorrent-pia-wireguard
```

2. Create and configure your environment file:
```bash
# Copy the example environment file
cp .env.example .env

# Edit .env with your PIA credentials
nano .env  # or use your preferred editor
```

Your `.env` file should contain:
```env
# PIA Credentials
PIA_USER=your_actual_username
PIA_PASS=your_actual_password
PIA_LOCATION=ireland  # or your preferred location

# Instance Configuration
INSTANCE_NAME=ireland  # Used for container naming
WEBUI_PORT=8080        # Port for accessing WebUI

# WebUI Credentials (IMPORTANT: Set a strong password!)
WEBUI_USERNAME=admin
WEBUI_PASSWORD=your_secure_password_here

# User/Group IDs (get with: id $(whoami))
PUID=1000
PGID=1000

# Timezone
TZ=Etc/UTC
```

**Security Note:** Always set a strong `WEBUI_PASSWORD`! This protects your qBittorrent WebUI from unauthorized access.

3. Deploy the stack:
```bash
docker-compose up -d

# Check logs to see auto-configuration
docker logs qbittorrent | grep "qbit-auto-config"

# Get the current forwarded port
docker exec pia-wireguard-ireland cat /pia-shared/port.dat

# Access qBittorrent WebUI
# http://your-server:8080
# Username: from WEBUI_USERNAME in .env (default: admin)
# Password: from WEBUI_PASSWORD in .env
```

### Available VPN Locations

To see all available PIA server locations, run:
```bash
docker run --rm thrnz/docker-wireguard-pia ./get-regions.sh
```

Popular locations include:
- `ireland` (default)
- `uk_london`
- `us_california`
- `us_east`
- `netherlands`
- `germany`
- `france`
- `australia`
- `japan`

Set your preferred location in the `.env` file:
```env
PIA_LOCATION=uk_london
```

## Running Multiple Instances

You can run multiple qBittorrent+VPN instances on the same system, each with different VPN locations and separate ports. This is useful for:

- Spreading load across multiple VPN servers
- Accessing different regional content
- Separating different types of torrents
- Improving overall download speeds

### Method 1: Separate Directories (Recommended)

Create separate directories for each instance:

```bash
# Create directory structure
mkdir -p ~/qbit-instances/{ireland,switzerland,netherlands}

# Clone or copy to each location
cd ~/qbit-instances/ireland
git clone https://github.com/yourusername/docker-qbittorrent-pia-wireguard.git .

cd ~/qbit-instances/switzerland
git clone https://github.com/yourusername/docker-qbittorrent-pia-wireguard.git .

cd ~/qbit-instances/netherlands
git clone https://github.com/yourusername/docker-qbittorrent-pia-wireguard.git .
```

Configure each instance with unique settings:

**~/qbit-instances/ireland/.env:**
```env
PIA_USER=your_pia_username
PIA_PASS=your_pia_password
PIA_LOCATION=ireland
INSTANCE_NAME=ireland
WEBUI_PORT=8080
WEBUI_USERNAME=admin
WEBUI_PASSWORD=your_password_here
PUID=1000
PGID=1000
TZ=Etc/UTC
```

**~/qbit-instances/switzerland/.env:**
```env
PIA_USER=your_pia_username
PIA_PASS=your_pia_password
PIA_LOCATION=switzerland
INSTANCE_NAME=switzerland
WEBUI_PORT=8081  # Different port!
WEBUI_USERNAME=admin
WEBUI_PASSWORD=your_password_here
PUID=1000
PGID=1000
TZ=Etc/UTC
```

**~/qbit-instances/netherlands/.env:**
```env
PIA_USER=your_pia_username
PIA_PASS=your_pia_password
PIA_LOCATION=netherlands
INSTANCE_NAME=netherlands
WEBUI_PORT=8082  # Different port!
WEBUI_USERNAME=admin
WEBUI_PASSWORD=your_password_here
PUID=1000
PGID=1000
TZ=Etc/UTC
```

Start each instance:
```bash
cd ~/qbit-instances/ireland && docker compose up -d
cd ~/qbit-instances/switzerland && docker compose up -d
cd ~/qbit-instances/netherlands && docker compose up -d
```

Access each WebUI:
- Ireland: http://your-server:8080
- Switzerland: http://your-server:8081
- Netherlands: http://your-server:8082

### Method 2: Single Directory with Docker Compose Projects

Use Docker Compose project names to run multiple instances from the same directory:

```bash
# Start Ireland instance
docker compose -p qbit-ireland up -d

# Start Switzerland instance with different .env
cp .env .env.switzerland
# Edit .env.switzerland with different INSTANCE_NAME, WEBUI_PORT, etc.
docker compose -p qbit-switzerland --env-file .env.switzerland up -d

# Start Netherlands instance
cp .env .env.netherlands
# Edit .env.netherlands with different INSTANCE_NAME, WEBUI_PORT, etc.
docker compose -p qbit-netherlands --env-file .env.netherlands up -d
```

### Multi-Instance Management

**View all instances:**
```bash
docker ps --filter "name=qbittorrent\|pia-wireguard"
```

**Stop a specific instance:**
```bash
# Using separate directories
cd ~/qbit-instances/ireland && docker compose down

# Using project names
docker compose -p qbit-ireland down
```

**Monitor all instances:**
```bash
# Check all forwarded ports
docker exec pia-wireguard-ireland cat /pia-shared/port.dat
docker exec pia-wireguard-switzerland cat /pia-shared/port.dat
docker exec pia-wireguard-netherlands cat /pia-shared/port.dat

# View logs for specific instance
docker logs qbittorrent-ireland 2>&1 | grep "qbit-auto-config"
```

### Important Notes for Multiple Instances

1. **Unique Ports:** Each instance MUST use a different `WEBUI_PORT`
2. **Unique Instance Names:** Use different `INSTANCE_NAME` values to avoid container naming conflicts
3. **Separate Volumes:** Each instance automatically gets separate Docker volumes (e.g., `qbittorrent-downloads-ireland`, `qbittorrent-downloads-switzerland`)
4. **Resource Usage:** Each instance uses ~200-300MB RAM and minimal CPU, but monitor your system resources
5. **VPN Connection Limits:** Check your PIA subscription for simultaneous connection limits

## How It Works

### 1. Pre-configured Settings

The `qbittorrent-config/qBittorrent/qBittorrent.conf` file contains pre-configured settings:

- **Network Interface**: `wg0` (VPN interface)
- **UPnP**: Disabled
- **Port**: Default 6881 (auto-updated on startup)
- **Protocol settings**: DHT, PeX, LSD enabled
- **Encryption**: Enabled
- **Connection limits**: Optimized

### 2. Automatic Port Configuration

The custom init script (`custom-init/99-update-qbit-port.sh`) runs on container startup and:

1. Waits for PIA to establish port forwarding
2. Reads the forwarded port from `/pia-shared/port.dat`
3. Updates qBittorrent's configuration file
4. Verifies VPN interface binding is correct
5. Ensures UPnP remains disabled

### 3. Volume Mounts

```yaml
volumes:
  # Pre-configured qBittorrent settings
  - ./qbittorrent-config:/config

  # Access to PIA port information
  - pia-shared:/pia-shared:ro

  # Custom initialization script
  - ./custom-init:/custom-cont-init.d:ro

  # Downloads (Docker volume)
  - qbittorrent-downloads:/downloads
```

## File Structure

```
docker-qbittorrent-pia-wireguard/
├── compose.yaml                            # Main compose file
├── .env.example                            # Environment variables template
├── .env                                    # Your credentials (create from .env.example)
├── qbittorrent-config/                     # Pre-configured settings
│   └── qBittorrent/
│       └── qBittorrent.conf                # qBittorrent configuration
├── custom-init/                            # Auto-configuration scripts
│   └── 99-update-qbit-port.sh             # Port update script
├── README.md                               # This file
├── CHANGES-DYNAMIC-PORT.md                # Technical details
└── LICENSE                                 # MIT License
```

**Note:** The `.env` file is gitignored and will not be committed to the repository.

## Configuration Details

### Network Interface Binding

The most critical setting for VPN safety:

```ini
[Preferences]
Connection\Interface=wg0
Connection\InterfaceName=wg0
```

This ensures **all** qBittorrent traffic goes through the VPN interface. If the VPN disconnects, qBittorrent will stop working (this is intentional for security).

### Port Forwarding

The init script automatically updates:

```ini
Connection\PortRangeMin=<forwarded_port>
```

The port changes when:
- Container restarts
- VPN reconnects
- Port lease expires (every 60 days with PORT_PERSIST=1)

### UPnP Disabled

```ini
Connection\UPnP=false
```

UPnP is dangerous with VPNs as it can expose your real IP through your router.

## Accessing Downloads

Downloads are stored in a Docker volume. To access them:

### List downloads
```bash
docker exec qbittorrent ls -lh /downloads
```

### Copy a file out
```bash
docker cp qbittorrent:/downloads/your-file.ext ./
```

### Access via bind mount (alternative)

If you want direct filesystem access, change the compose.yaml:

```yaml
volumes:
  - ./downloads:/downloads  # Instead of qbittorrent-downloads:/downloads
```

## Monitoring

### Check current configuration
```bash
docker exec qbittorrent cat /config/qBittorrent/qBittorrent.conf | grep -A3 "Connection\\\\"
```

### Check current forwarded port
```bash
docker exec pia-wireguard-ireland cat /pia-shared/port.dat
```

### View auto-configuration logs
```bash
docker logs qbittorrent 2>&1 | grep "qbit-auto-config"
```

### Verify VPN IP
```bash
docker exec pia-wireguard-ireland curl https://ipinfo.io
```

## No Docker Port Mapping Needed for Peer Connections

**Important:** The BitTorrent peer port does **NOT** need to be in Docker's port mapping!

### Why?

Peer connections work like this:
```
Internet Peers → VPN Server → WireGuard Tunnel → Container wg0 → qBittorrent
```

This traffic flow **bypasses Docker's port mapping entirely**. Docker port mapping only affects connections from your local network to the container.

### What's Configured Automatically

✅ **qBittorrent listening port** - Auto-configured by the init script to match PIA's forwarded port
✅ **PIA firewall** - Automatically allows the forwarded port
✅ **Network interface** - qBittorrent bound to wg0 (VPN interface)

### Current Port Mapping (WebUI Only)

```yaml
ports:
  - "8080:8080"  # Only for accessing WebUI from your local network
```

The BitTorrent port is intentionally **not** mapped because:
- Peers connect through the VPN tunnel (not Docker bridge)
- No manual updates needed when PIA assigns a new port
- Fully automated port forwarding

## Troubleshooting

### Port not updating automatically

Check the init script logs:
```bash
docker logs qbittorrent 2>&1 | grep "qbit-auto-config"
```

Common issues:
- PIA port forwarding not ready yet (script waits up to 60 seconds)
- Permission issues with /pia-shared volume

### qBittorrent not bound to VPN

Verify interface setting:
```bash
docker exec qbittorrent cat /config/qBittorrent/qBittorrent.conf | grep "Interface"
```

Should show:
```
Connection\Interface=wg0
Connection\InterfaceName=wg0
```

### Testing VPN binding

Stop the VPN container and verify qBittorrent stops all traffic:
```bash
docker stop pia-wireguard-ireland
```

qBittorrent should show all torrents as "stalled" - this means it's properly bound to the VPN interface.

### Configuration not persisting

If you're using Komodo or deploying to a remote server, ensure the `./qbittorrent-config` and `./custom-init` directories exist on the server at the compose file location.

For Komodo, you may need to:
1. Create these directories on the server first
2. Upload the files via SCP or Komodo's file manager
3. Then deploy the stack

## Security Notes

1. **Interface binding** - The `wg0` binding ensures no leaks if VPN disconnects
2. **Firewall** - The PIA container has firewall enabled, dropping non-VPN traffic
3. **UPnP disabled** - Prevents router from exposing your real IP
4. **No split tunneling** - All qBittorrent traffic goes through VPN
5. **WebUI credentials** - Always set a strong `WEBUI_PASSWORD` in your `.env` file
6. **User permissions** - Proper `PUID`/`PGID` settings prevent privilege escalation

## Customization

All major settings can be configured via the `.env` file:

### Change VPN location

```env
PIA_LOCATION=netherlands  # or any other PIA region
```

### Change WebUI port

```env
WEBUI_PORT=8090  # Automatically updates both container config and port mapping
```

### Change WebUI credentials

```env
WEBUI_USERNAME=myusername
WEBUI_PASSWORD=my_secure_password_123
```

### Change user/group for file permissions

```env
# Get your IDs with: id $(whoami)
PUID=1001
PGID=1001
```

### Change timezone

```env
TZ=America/New_York  # or Europe/London, Asia/Tokyo, etc.
```

### Adjust connection limits

Edit `qbittorrent-config/qBittorrent/qBittorrent.conf`:
```ini
Connection\GlobalMaxConnections=1000
Connection\MaxConnectionsPerTorrent=256
```

### Change download location

Currently using Docker volume. To use host directory:
```yaml
volumes:
  - /path/to/downloads:/downloads
```

## Advanced: Manual Configuration

If you need to manually configure additional settings:

1. Access WebUI at http://your-server:8080
2. Go to Tools → Options
3. Make changes
4. Changes persist in `./qbittorrent-config/qBittorrent/qBittorrent.conf`

**Note**: The init script will override:
- Port settings (reads from PIA)
- Interface binding (always sets to wg0)
- UPnP setting (always disabled)

Other settings you configure manually will persist.

## Verification Checklist

After deployment, verify:

- [ ] VPN connected: `docker logs pia-wireguard-ireland | grep "successfully started"`
- [ ] Port forwarding active: `docker exec pia-wireguard-ireland cat /pia-shared/port.dat`
- [ ] qBittorrent running: `docker ps | grep qbittorrent`
- [ ] Auto-config ran: `docker logs qbittorrent | grep "qbit-auto-config"`
- [ ] WebUI accessible: http://your-server:8080
- [ ] Interface bound to wg0: Check Tools → Options → Advanced → Network Interface
- [ ] UPnP disabled: Check Tools → Options → Connection

## Support

If you encounter issues:

1. Check container logs: `docker logs <container-name>`
2. Verify file permissions on mounted directories
3. Ensure Docker volumes have proper access
4. Check that both containers are running: `docker ps`

For PIA-specific issues, see: https://github.com/thrnz/docker-wireguard-pia
For qBittorrent issues, see: https://docs.linuxserver.io/images/docker-qbittorrent/
