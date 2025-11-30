# qBittorrent + PIA VPN with Automatic Port Forwarding

Fully automated Docker setup for qBittorrent with Private Internet Access (PIA) VPN using WireGuard. Zero manual configuration required.

## Features

✅ **Automatic VPN binding** - qBittorrent automatically binds to `wg0` interface
✅ **Auto port forwarding** - Dynamically reads and configures PIA's forwarded port
✅ **Automatic port monitoring** - Background service detects port changes and updates qBittorrent in real-time
✅ **UPnP disabled** - Prevents accidental IP leaks
✅ **Pre-configured settings** - Optimized for VPN usage out of the box
✅ **Persistent configuration** - Settings survive container restarts
✅ **No hardcoded ports** - Handles PIA's dynamic port changes automatically
✅ **Multi-instance support** - Run multiple instances on the same system with different VPN locations
✅ **Health monitoring** - Automatic container restart on VPN or WebUI failures
✅ **Optional Firefox browser** - Access private tracker sites through the same VPN IP as qBittorrent

## Use Case: Scalable Long-Term Seeding

This project is designed for **indefinite seeding with horizontal scaling**. The strategy:

1. **Seed forever** - Use hardlinks so files exist in both your media library and qBittorrent's download folder without using extra disk space. Deleting from your library doesn't affect seeding.

2. **Scale when saturated** - When your upload bandwidth to one VPN server maxes out, spin up a new stack on a different VPN location. The old stack keeps seeding existing torrents.

3. **Repeat** - Each stack is independent with its own VPN connection. Add stacks as needed to maximize your seeding capacity.

**Example progression:**
```
Week 1:  Stack 1 (Denmark)     → 50 torrents, 80% upload capacity
Week 4:  Stack 1 (Denmark)     → 200 torrents, 100% upload (saturated)
         Stack 2 (Switzerland) → New downloads go here
Week 8:  Stack 1 (Denmark)     → 200 torrents, still seeding
         Stack 2 (Switzerland) → 150 torrents, 100% upload (saturated)
         Stack 3 (Netherlands) → New downloads go here
```

Each stack maintains its own:
- VPN tunnel with unique forwarded port
- qBittorrent instance with separate config
- Download directory (can use hardlinks to shared media library)

This architecture lets you contribute back to the torrent community at scale while keeping your media library organized with Sonarr/Radarr.

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
PIA_LOCATION=denmark  # Choose from available locations

# Instance Configuration
INSTANCE_NAME=tv-01    # Used for container naming
WEBUI_PORT=8080        # Port for accessing WebUI

# User/Group IDs (get with: id $(whoami))
PUID=1000
PGID=1000

# Timezone
TZ=Etc/UTC
```

3. Deploy the stack:
```bash
docker-compose up -d

# Check logs to see auto-configuration
docker logs qbittorrent | grep "qbit-auto-config"

# Get the current forwarded port
docker exec pia-wireguard-${INSTANCE_NAME} cat /pia-shared/port.dat

# Access qBittorrent WebUI
# http://your-server:8080
# Username: admin
# Password: Check logs for temporary password on first start
docker logs qbittorrent | grep "password"
```

### Available VPN Locations

**CRITICAL:** For qBittorrent to work properly with port forwarding, you **CANNOT use US locations**. All US servers do NOT support port forwarding, which results in slower speeds and fewer peer connections.

#### List All Available Locations

To see all available PIA server locations from the official server list:

```bash
curl -s https://serverlist.piaservers.net/vpninfo/servers/v6 | \
  python3 -c "
import sys, json
raw = sys.stdin.read()
data = json.JSONDecoder().raw_decode(raw)[0]
for r in sorted(data['regions'], key=lambda x: x['name']):
    pf = '✓ YES' if r['port_forward'] else '✗ NO'
    print(f\"{r['name']:35} ({r['country']}) - ID: {r['id']:25} - Port Forwarding: {pf}\")
"
```

This will show all locations with their IDs and port forwarding support.

#### Port Forwarding Summary

- **✓ All international locations** (Europe, Asia, Canada, Australia, etc.) support port forwarding
- **✗ All US locations** do NOT support port forwarding

#### Recommended Locations (with port forwarding)

Popular locations that support port forwarding:
- `denmark` - Denmark
- `swiss` - Switzerland
- `ireland` - Ireland
- `nl_amsterdam` - Netherlands
- `uk` - UK London
- `de_frankfurt` - Germany Frankfurt
- `france` - France
- `denmark` - Denmark
- `sweden` - Sweden
- `aus` - Australia Sydney
- `japan` - Japan Tokyo
- `sg` - Singapore
- `ca_toronto` - Canada Toronto

Set your preferred location in the `.env` file:
```env
PIA_LOCATION=swiss
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
mkdir -p ~/qbit-instances/{tv-01,movies-01,books-01}

# Clone or copy to each location
cd ~/qbit-instances/tv-01
git clone https://github.com/jq6l43d1/docker-qbittorrent-pia-wireguard.git .

cd ~/qbit-instances/movies-01
git clone https://github.com/jq6l43d1/docker-qbittorrent-pia-wireguard.git .

cd ~/qbit-instances/books-01
git clone https://github.com/jq6l43d1/docker-qbittorrent-pia-wireguard.git .
```

Configure each instance with unique settings:

**~/qbit-instances/tv-01/.env:**
```env
PIA_USER=your_pia_username
PIA_PASS=your_pia_password
PIA_LOCATION=denmark
INSTANCE_NAME=tv-01
WEBUI_PORT=8080
PUID=1000
PGID=1000
TZ=Etc/UTC
```

**~/qbit-instances/movies-01/.env:**
```env
PIA_USER=your_pia_username
PIA_PASS=your_pia_password
PIA_LOCATION=mexico
INSTANCE_NAME=movies-01
WEBUI_PORT=8081  # Different port!
PUID=1000
PGID=1000
TZ=Etc/UTC
```

**~/qbit-instances/books-01/.env:**
```env
PIA_USER=your_pia_username
PIA_PASS=your_pia_password
PIA_LOCATION=switzerland
INSTANCE_NAME=books-01
WEBUI_PORT=8082  # Different port!
PUID=1000
PGID=1000
TZ=Etc/UTC
```

Start each instance:
```bash
cd ~/qbit-instances/tv-01 && docker compose up -d
cd ~/qbit-instances/movies-01 && docker compose up -d
cd ~/qbit-instances/books-01 && docker compose up -d
```

Access each WebUI:
- TV: http://your-server:8080
- Movies: http://your-server:8081
- Books: http://your-server:8082

### Method 2: Single Directory with Docker Compose Projects

Use Docker Compose project names to run multiple instances from the same directory:

```bash
# Start first instance
docker compose -p qbit-tv-01 up -d

# Start second instance with different .env
cp .env .env.movies
# Edit .env.movies with different INSTANCE_NAME, WEBUI_PORT, etc.
docker compose -p qbit-movies-01 --env-file .env.movies up -d

# Start third instance
cp .env .env.books
# Edit .env.books with different INSTANCE_NAME, WEBUI_PORT, etc.
docker compose -p qbit-books-01 --env-file .env.books up -d
```

### Multi-Instance Management

**View all instances:**
```bash
docker ps --filter "name=qbittorrent\|pia-wireguard"
```

**Stop a specific instance:**
```bash
# Using separate directories
cd ~/qbit-instances/tv-01 && docker compose down

# Using project names
docker compose -p qbit-tv-01 down
```

**Monitor all instances:**
```bash
# Check all forwarded ports
docker exec pia-wireguard-tv-01 cat /pia-shared/port.dat
docker exec pia-wireguard-movies-01 cat /pia-shared/port.dat
docker exec pia-wireguard-books-01 cat /pia-shared/port.dat

# View logs for specific instance
docker logs qbittorrent-tv-01 2>&1 | grep "qbit-auto-config"
```

### Important Notes for Multiple Instances

1. **Unique Ports:** Each instance MUST use a different `WEBUI_PORT`
2. **Unique Instance Names:** Use different `INSTANCE_NAME` values to avoid container naming conflicts
3. **Separate Volumes:** Each instance automatically gets separate Docker volumes:
   - Config: `qbittorrent-config-${INSTANCE_NAME}` (isolated settings, prevents lockfile conflicts)
   - PIA shared: `pia-shared-${INSTANCE_NAME}` (VPN port forwarding data)
   - Downloads can be bind-mounted to host directories (e.g., `/path/to/downloads/${INSTANCE_NAME}`)
4. **Resource Usage:** Each instance uses ~200-300MB RAM and minimal CPU, but monitor your system resources
5. **VPN Connection Limits:** Check your PIA subscription for simultaneous connection limits

## Optional: Firefox Browser Through VPN

Some private trackers require your browser IP to match your torrent client IP. This stack includes an optional Firefox browser that routes through the same VPN tunnel as qBittorrent.

### Enable Firefox

Set `ENABLE_FIREFOX=1` in your `.env` file:

```env
ENABLE_FIREFOX=1
```

Then start or redeploy the stack:

```bash
docker compose up -d
```

### Access Firefox

- **HTTPS (recommended):** `https://your-server:3001`
- **HTTP:** `http://your-server:3000`

The browser runs in a container and is accessed through your web browser via noVNC.

### Verify Same IP

1. In Firefox (through VPN), visit https://whatismyip.com
2. In qBittorrent WebUI, check Tools → Connection status
3. Both should show the same VPN IP address

### Port Configuration

Configure Firefox ports in your `.env` file:

```env
FIREFOX_PORT=3000        # HTTP access
FIREFOX_PORT_HTTPS=3001  # HTTPS access (recommended)
```

When running multiple instances, use different ports:

| Instance | FIREFOX_PORT | FIREFOX_PORT_HTTPS |
|----------|--------------|-------------------|
| tv-01 | 3000 | 3001 |
| movies-01 | 3002 | 3003 |
| books-01 | 3004 | 3005 |

### Security Warning

The Firefox container provides full browser access. **Do not expose it to the internet** without proper authentication. It's designed for local network access only.

### Disable Firefox

To disable Firefox, set `ENABLE_FIREFOX=0` in your `.env` file (this is the default):

```env
ENABLE_FIREFOX=0
```

Then redeploy:

```bash
docker compose up -d
```

## How It Works

### 1. Instance-Specific Configuration

Each instance gets its own isolated configuration in a Docker volume (`qbittorrent-config-${INSTANCE_NAME}`):

- **Network Interface**: `wg0` (VPN interface) - auto-configured by init script
- **UPnP**: Disabled - prevents IP leaks
- **Port**: Default 6881 (auto-updated on startup to match PIA's forwarded port)
- **Protocol settings**: DHT, PeX, LSD enabled
- **Encryption**: Enabled
- **Connection limits**: Optimized

The init script automatically configures these settings on first startup. Each instance's configuration is completely isolated, preventing lockfile and socket conflicts between instances.

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
  # Instance-specific qBittorrent config (Docker volume)
  - qbittorrent-config:/config

  # Access to PIA port information
  - pia-shared:/pia-shared:ro

  # Custom initialization script
  - ./custom-init:/custom-cont-init.d:ro

  # Custom services (port monitoring)
  - ./custom-services.d:/custom-services.d:ro

  # Downloads (bind mount to host or Docker volume)
  - /path/to/downloads/${INSTANCE_NAME}:/downloads
```

**Config Volume:** Each instance uses its own `qbittorrent-config-${INSTANCE_NAME}` Docker volume. This prevents multiple instances from conflicting over lockfiles and IPC sockets.

## File Structure

```
docker-qbittorrent-pia-wireguard/
├── compose.yaml                            # Main compose file
├── .env.example                            # Environment variables template
├── .env                                    # Your credentials (create from .env.example)
├── qbittorrent-config/                     # Example config (reference only)
│   └── qBittorrent/
│       └── qBittorrent.conf                # Default configuration template
├── custom-init/                            # Auto-configuration scripts
│   └── 99-update-qbit-port.sh             # Port update script
├── custom-services.d/                      # Background services
│   └── port-monitor                        # Automatic port change detection
├── README.md                               # This file
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

Port forwarding is configured automatically in two ways:

**1. At Container Startup**
The init script configures the initial port:

```ini
Connection\PortRangeMin=<forwarded_port>
```

**2. Automatic Port Change Detection**
A background monitoring service watches for port changes and automatically:
- Detects when PIA assigns a new port
- Updates qBittorrent configuration
- Restarts qBittorrent process to apply changes
- Logs all port changes for auditing

Port changes occur when:
- Container restarts
- VPN reconnects
- Port lease expires (every 60 days with PORT_PERSIST=1)

With automatic monitoring, qBittorrent **always uses the current port** without manual intervention.

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
  - ./downloads:/downloads  # Instead of /alexandria/${INSTANCE_NAME}:/downloads
```

## Hardlink Support for Sonarr/Radarr

When using qBittorrent with Sonarr, Radarr, or other *arr apps, you want **hardlinks** instead of copies. Hardlinks allow the file to exist in both the download location (for seeding) and the media library without using extra disk space.

### Why Hardlinks Fail

Hardlinks **cannot cross mount point boundaries**. If your downloads and media library are separate mounts, the *arr app will copy files instead of hardlinking them.

**Example of broken setup:**
```
/downloads  → mounted from /alexandria/tv-01
/tv         → mounted from /alexandria/tv
```
Even though both are on the same physical disk, they're separate mounts, so hardlinks fail.

### Solution: Single Mount Point

Mount a common parent directory to both containers, then configure applications to use subdirectories under that single mount.

### Proxmox LXC Setup

If running qBittorrent in a Docker container inside an LXC, and Sonarr in another LXC:

**Step 1: Configure LXC Mount Points**

Both containers need the same storage mounted at the same path:

```bash
# Container running Docker (qBittorrent)
# /etc/pve/lxc/105.conf
mp0: /alexandria,mp=/data

# Container running Sonarr
# /etc/pve/lxc/100.conf
mp0: /alexandria,mp=/data
```

**Step 2: Update Docker Compose**

Change the volume mount from instance-specific to the shared `/data`:

```yaml
# compose.yaml
volumes:
  - /data:/data  # Instead of /alexandria/${INSTANCE_NAME}:/downloads
```

**Step 3: Configure qBittorrent**

In qBittorrent WebUI → Settings → Downloads:
- **Default Save Path:** `/data/tv-01` (or your instance folder)

**Step 4: Configure Sonarr**

1. **Root Folders:** Settings → Media Management → Root Folders
   - Add: `/data/tv`

2. **Download Client:** Settings → Download Clients → qBittorrent
   - No remote path mapping needed (paths are now identical)

3. **Existing Series:** Series → Mass Editor
   - Select all → Change Root Folder to `/data/tv`

### Path Mapping Summary

| Component | Path | Maps To (Host) |
|-----------|------|----------------|
| qBittorrent downloads | `/data/tv-01` | `/alexandria/tv-01` |
| Sonarr library | `/data/tv` | `/alexandria/tv` |
| Sonarr sees downloads | `/data/tv-01` | `/alexandria/tv-01` |

Both paths share the `/data` mount point, enabling hardlinks.

### Verify Hardlinks Are Working

**Method 1: Check Sonarr Activity**

After importing, Sonarr's Activity log should show:
- ✅ "Hardlinking movie file" (working)
- ❌ "Copying movie file" (not working)

**Method 2: Compare Inodes**

Files with the same inode number are hardlinked:

```bash
# Run in Sonarr container
ls -li /data/tv/ShowName/Season\ 1/episode.mkv /data/tv-01/episode.mkv
```

Output showing same inode (first column):
```
15959 -rw-r--r-- 2 1000 1000 193098726 Nov 25 15:00 /data/tv-01/episode.mkv
15959 -rw-r--r-- 2 1000 1000 193098726 Nov 25 15:00 /data/tv/ShowName/Season 1/episode.mkv
```

The `2` in the third column indicates 2 hardlinks to the same file.

### Multiple Instances

For multiple qBittorrent instances (tv-01, movies-01, books-01), use the same `/data:/data` mount for all:

```
/data/
├── tv/              # Sonarr library
├── tv-01/           # qBittorrent TV downloads
├── movies/          # Radarr library
├── movies-01/       # qBittorrent movie downloads
├── books/           # Readarr library
└── books-01/        # qBittorrent book downloads
```

Each *arr app points to its library folder and sees downloads in the corresponding instance folder.

## Monitoring

### Check current configuration
```bash
docker exec qbittorrent cat /config/qBittorrent/qBittorrent.conf | grep -A3 "Connection\\\\"
```

### Check current forwarded port
```bash
docker exec pia-wireguard-${INSTANCE_NAME} cat /pia-shared/port.dat
```

### View auto-configuration logs
```bash
docker logs qbittorrent 2>&1 | grep "qbit-auto-config"
```

### Monitor automatic port changes
```bash
# View port monitoring service logs
docker logs qbittorrent 2>&1 | grep "port-monitor"

# Watch for port changes in real-time
docker logs -f qbittorrent 2>&1 | grep "port-monitor"

# Check if monitoring service is running
docker exec qbittorrent ps aux | grep "port-monitor"
```

When a port change is detected, you'll see logs like:
```
[port-monitor] ==========================================
[port-monitor] PORT CHANGE DETECTED!
[port-monitor] Old port: 12345
[port-monitor] New port: 54321
[port-monitor] ==========================================
[port-monitor] Config backed up
[port-monitor] Configuration updated successfully
[port-monitor] Restarting qBittorrent process to apply changes...
[port-monitor] qBittorrent restart triggered
[port-monitor] Port updated from 12345 to 54321
[port-monitor] ==========================================
```

**Note:** qBittorrent will briefly disconnect (typically <5 seconds) during port updates. Active torrents will pause momentarily and resume automatically.

### Verify VPN IP
```bash
docker exec pia-wireguard-${INSTANCE_NAME} curl https://ipinfo.io
```

### Health Checks and Container Status

Both containers have automatic health monitoring enabled:

**View health status:**
```bash
# Quick status check
docker compose ps

# Detailed health check information
docker inspect pia-wireguard-${INSTANCE_NAME} | grep -A 10 Health
docker inspect qbittorrent-${INSTANCE_NAME} | grep -A 10 Health
```

**Health check behavior:**
- **pia-wireguard**: Pings through the VPN tunnel every 1 minute
  - If 3 consecutive pings fail (3 minutes), container is marked unhealthy
  - Container will automatically restart due to `restart: unless-stopped` policy

- **qbittorrent**: Checks WebUI responsiveness every 30 seconds
  - If 3 consecutive checks fail (90 seconds), container is marked unhealthy
  - qBittorrent waits for pia-wireguard to be healthy before starting

**Healthy output looks like:**
```
NAME                        STATUS                   PORTS
pia-wireguard-tv-01        Up 10 minutes (healthy)  0.0.0.0:8080->8080/tcp
qbittorrent-tv-01          Up 9 minutes (healthy)
```

**Troubleshooting unhealthy containers:**
```bash
# View recent health check logs
docker inspect pia-wireguard-${INSTANCE_NAME} --format='{{json .State.Health}}' | jq

# Check why health checks are failing
docker logs pia-wireguard-${INSTANCE_NAME} --tail 50
docker logs qbittorrent-${INSTANCE_NAME} --tail 50

# Manually test VPN connectivity
docker exec pia-wireguard-${INSTANCE_NAME} ping -c 3 1.1.1.1

# Manually test qBittorrent WebUI
docker exec qbittorrent-${INSTANCE_NAME} curl -f http://localhost:${WEBUI_PORT}
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
docker stop pia-wireguard-${INSTANCE_NAME}
```

qBittorrent should show all torrents as "stalled" - this means it's properly bound to the VPN interface.

### Configuration not persisting

Configuration is stored in Docker volumes (`qbittorrent-config-${INSTANCE_NAME}`), so it persists across container recreations.

If using a management platform like Komodo:
1. Ensure the `./custom-init` and `./custom-services.d` directories are accessible to the deployment
2. Each instance's configuration is isolated in its own Docker volume
3. To reset an instance's config, remove its volume: `docker volume rm qbittorrent-config-instance-name`

## Security Notes

1. **Interface binding** - The `wg0` binding ensures no leaks if VPN disconnects
2. **Firewall** - The PIA container has firewall enabled, dropping non-VPN traffic
3. **UPnP disabled** - Prevents router from exposing your real IP
4. **No split tunneling** - All qBittorrent traffic goes through VPN
5. **WebUI security** - Change the default password in Tools → Options → Web UI after first login
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

### Change WebUI password

Change the password in the WebUI after first login:
1. Access WebUI and login with the temporary password from logs
2. Go to Tools → Options → Web UI
3. Set a new username and password
4. Click Save

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

Modify settings via WebUI (Tools → Options → Connection) or by editing the config in the Docker volume:
```bash
# Find the volume path
docker volume inspect qbittorrent-config-instance-name

# Edit the config (requires container restart)
docker exec qbittorrent-instance-name vi /config/qBittorrent/qBittorrent.conf
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
4. Changes persist in the instance's Docker volume (`qbittorrent-config-${INSTANCE_NAME}`)

**Note**: The init script will override:
- Port settings (reads from PIA)
- Interface binding (always sets to wg0)
- UPnP setting (always disabled)

Other settings you configure manually will persist.

## Verification Checklist

After deployment, verify:

- [ ] VPN connected: `docker logs pia-wireguard-${INSTANCE_NAME} | grep "successfully started"`
- [ ] Port forwarding active: `docker exec pia-wireguard-${INSTANCE_NAME} cat /pia-shared/port.dat`
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
