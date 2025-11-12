# Changes Made: Fully Automated Dynamic Port Forwarding

## Summary

Removed the hardcoded BitTorrent port from docker-compose.yml to eliminate the need for manual updates when PIA assigns a new forwarded port.

## What Changed

### docker-compose-qbittorrent-vpn.yml

**Before:**
```yaml
ports:
  - "8080:8080"
  - "25852:25852"  # Had to manually update this
```

**After:**
```yaml
ports:
  - "8080:8080"  # Only WebUI needed
```

### Why This Works

When using `network_mode: "container:pia-wireguard-ireland"`, qBittorrent shares the VPN container's entire network namespace. This means:

1. **Peer connections flow:** `Internet → VPN Server → WireGuard Tunnel → Container wg0 → qBittorrent`
2. **Docker port mapping is for:** `Local Network → Docker Bridge → Container`
3. **These are completely separate paths!**

For peer connections:
- Traffic enters through the VPN tunnel (not Docker's port mapping)
- PIA firewall already allows the forwarded port
- qBittorrent is auto-configured to listen on the correct port (via your init script)
- Docker port mapping is irrelevant

## What Still Works (Automated)

✅ **qBittorrent Listening Port Configuration**
- Script: `custom-init/99-update-qbit-port.sh`
- Reads: `/pia-shared/port.dat`
- Updates: qBittorrent's `Connection\PortRangeMin` setting
- When: Every container startup

✅ **PIA Firewall Rules**
- Automatically allows forwarded port
- Logs show: `[pf] Allowing incoming traffic on port XXXXX`

✅ **VPN Interface Binding**
- qBittorrent bound to `wg0` interface
- Pre-configured in: `qbittorrent-config/qBittorrent/qBittorrent.conf`
- Verified by init script

✅ **UPnP Disabled**
- Prevents IP leaks through router
- Pre-configured and verified

## Benefits

### Before (Manual Process)
1. Check current forwarded port: `cat /pia-shared/port.dat`
2. Edit docker-compose.yml with new port
3. Redeploy stack
4. Hope you remembered to do this

### After (Fully Automated)
1. *(Nothing - it just works)*

## Verification Steps

After deploying the updated docker-compose.yml:

### 1. Verify qBittorrent is configured correctly
```bash
docker logs qbittorrent 2>&1 | grep "qbit-auto-config"
```

Expected output:
```
[qbit-auto-config] Found PIA forwarded port: XXXXX
[qbit-auto-config] Configuration updated successfully!
[qbit-auto-config] - Port: XXXXX
[qbit-auto-config] - Interface: wg0
[qbit-auto-config] - UPnP: disabled
```

### 2. Check current forwarded port
```bash
docker exec pia-wireguard-ireland cat /pia-shared/port.dat
```

### 3. Verify qBittorrent WebUI shows correct port
1. Access WebUI: `http://your-server:8080`
2. Go to: **Tools → Options → Connection**
3. Check: **Port used for incoming connections**
4. Should match the port from step 2

### 4. Verify network interface binding
1. In WebUI: **Tools → Options → Advanced**
2. Check: **Network Interface**
3. Should show: `wg0`

### 5. Test peer connectivity (after adding torrents)

Wait a few minutes, then check if peers are connecting:
- Look for upload/download activity in WebUI
- Check peer count on active torrents
- Verify you're not stuck on "Downloading metadata" or "Stalled"

## Technical Details

### Network Flow Diagram

```
┌─────────────────────────────────────────────────┐
│ Internet Peers                                   │
└──────────────┬──────────────────────────────────┘
               │
               ▼
        VPN Server (PIA)
               │
               ▼
        WireGuard Tunnel
               │
               ▼
┌──────────────┴──────────────────────────────────┐
│ Container Network Namespace (shared)             │
│  ┌────────────────────────────────────────────┐ │
│  │ wg0 interface (10.x.x.x)                   │ │
│  │ - PIA firewall allows port XXXXX          │ │
│  │ - qBittorrent listens on port XXXXX       │ │
│  └────────────────────────────────────────────┘ │
│                                                   │
│  pia-wireguard-ireland container                 │
│  qbittorrent container (same network namespace)  │
└───────────────────────────────────────────────────┘
               ▲
               │
     Docker Port Mapping
     (8080:8080 for WebUI only)
               │
               │
        Your Local Network
```

### Key Insight

Docker's `network_mode: "container:xxx"` means the qBittorrent container doesn't have its own network stack. It's literally using the VPN container's network interfaces, IP addresses, and firewall rules.

When a peer connects to your VPN IP on the forwarded port, the traffic is already "inside" the container's network namespace. Docker port mapping (`-p` or `ports:`) is only for mapping from the **host** to the container, which is irrelevant for VPN traffic.

## Troubleshooting

### If peers aren't connecting

1. **Check auto-config ran successfully:**
   ```bash
   docker logs qbittorrent 2>&1 | grep "qbit-auto-config"
   ```

2. **Verify port matches:**
   ```bash
   # Get PIA port
   PIA_PORT=$(docker exec pia-wireguard-ireland cat /pia-shared/port.dat)
   echo "PIA Port: $PIA_PORT"

   # Get qBittorrent port
   QB_PORT=$(docker exec qbittorrent cat /config/qBittorrent/qBittorrent.conf | grep "PortRangeMin" | cut -d= -f2)
   echo "qBittorrent Port: $QB_PORT"

   # Should match!
   ```

3. **Check interface binding:**
   ```bash
   docker exec qbittorrent cat /config/qBittorrent/qBittorrent.conf | grep "Interface"
   ```
   Should show: `Connection\Interface=wg0`

4. **Verify VPN is connected:**
   ```bash
   docker logs pia-wireguard-ireland | grep "successfully started"
   ```

5. **Test VPN IP:**
   ```bash
   docker exec pia-wireguard-ireland curl https://ipinfo.io
   ```
   Should show your VPN IP, not your real IP

### If WebUI isn't accessible

The WebUI port (8080) **is** mapped and should work from your local network. If not:

```bash
# Check if port is exposed
docker port pia-wireguard-ireland

# Should show:
# 8080/tcp -> 0.0.0.0:8080
```

## Files Modified

1. `docker-compose-qbittorrent-vpn.yml` - Removed hardcoded BitTorrent port
2. `README-AUTO-CONFIG.md` - Updated documentation to clarify port mapping

## Files Unchanged (Still Working)

- `qbittorrent-config/qBittorrent/qBittorrent.conf` - Pre-configured settings
- `custom-init/99-update-qbit-port.sh` - Auto-configuration script

## Conclusion

Your setup is now **fully automated**:
- No manual port updates needed
- No redeployments when port changes
- Port forwarding just works
- Zero maintenance required

The auto-configuration script handles everything, and removing the hardcoded port mapping eliminates the one manual step that was left.
