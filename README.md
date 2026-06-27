# Home Assistant with Cloudflare Tunnel

Expose Home Assistant to the internet via Cloudflare Tunnel while maintaining local network discovery.

## Architecture

```
Internet → Cloudflare → Tunnel → web network → Home Assistant
                                              ↓
                                  default network → MQTT, Zigbee2MQTT, AppDaemon
```

Home Assistant on two networks:
- **web**: External access via tunnel
- **default**: Internal services (MQTT, Zigbee2MQTT, AppDaemon)

## Setup

### 1. Network Override

`overrides/home-assistant.override.yaml`:

```yaml
services:
  homeassistant:
    networks:
      - default
      - web

networks:
  web:
    external: true
    name: web
```

Link it:
```bash
cd services/home-assistant
ln -sf ../../overrides/home-assistant.override.yaml docker-compose.override.yaml
```

### 2. Service Configuration

**MQTT**: Change from `192.168.1.x` to `mqtt` in configuration.yaml or UI

**AppDaemon** `appdaemon.yaml`:
```yaml
appdaemon:
  plugins:
    HASS:
      ha_url: !env_var HA_URL
      token: !env_var HA_TOKEN
```

`.env`:
```bash
HA_URL=http://homeassistant:8123
HA_TOKEN=your_long_lived_token
```

### 4. Configure Reverse Proxy

`home_assistant/configuration.yaml`:
```yaml
http:
  use_x_forwarded_for: true
  trusted_proxies:
    - 172.22.0.0/16
```

### 4. Cloudflare Route

Add public hostname:
- Subdomain: `ha`
- Domain: `yourdomain.com`
- Service: `http://homeassistant:8123`

### 5. Deploy

```bash
docker compose down
docker compose up -d
```

### 6. Configure HA

- Settings → System → Network → Home Assistant URL: `https://ha.yourdomain.com`
- Enable 2FA: Profile → Two-factor Authentication

## Troubleshooting

**Devices not responding**: Verify MQTT broker uses `mqtt` hostname

**400 Bad Request**: Add `trusted_proxies` to configuration.yaml

**Sonos discovery fails**: Check ports 1900/udp and 5353/udp in docker-compose.yaml

**AppDaemon connection**: Verify `ha_url` uses `homeassistant` hostname

## Security

- Traffic encrypted via Cloudflare SSL
- Only `web` network (172.22.0.0/16) trusted as reverse proxy
- Enable 2FA for additional protection
- No ports directly exposed to internet

## Docker Container Access to Additional VLANs

**Problem:** Docker containers on bridge networks cannot reach devices on VLANs other than the host's primary subnet.

**Solution:** Add static route on Docker host. Bridge network containers automatically inherit the host's routing table.

**Steps:**

1. **Add temporary route to test:**
```bash
   sudo ip route add <VLAN_SUBNET>/24 via <ROUTER_IP>
```

2. **Make permanent (Ubuntu/Netplan):**
   Edit `/etc/netplan/*.yaml` and add to routes section:
```yaml
   routes:
     - to: <VLAN_SUBNET>/24
       via: <ROUTER_IP>
```
   Apply: `sudo netplan apply`

3. **Configure router firewall:** Allow traffic between subnets as needed.

Note: Containers on Docker bridge networks use the host's routing table - no special network modes required.
