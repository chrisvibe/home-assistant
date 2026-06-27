# Home Assistant — Emergency Runbook

**Current versions:** HA 2026.6.4 · Zigbee2MQTT 2.12.0 · Mosquitto 2.0.22 · Postgres 16-alpine  
**Previous versions:** HA 2026.4.1 · Zigbee2MQTT 2.7

---

## Quick check

```bash
docker compose ps
curl -sf http://localhost:8123 && echo OK
docker compose logs --tail=30 homeassistant
```

Containers: `homeassistant` · `ha-postgres` · `ha-postgres-backup` · `zigbee2mqtt` · `mqtt`

---

## Rollback Home Assistant

```bash
git log --oneline -5 docker-compose.yaml

sed -i 's|home-assistant:2026.6.4|home-assistant:2026.4.1|' docker-compose.yaml
docker compose pull homeassistant
docker compose up -d homeassistant
docker compose logs -f homeassistant
```

## Rollback Zigbee2MQTT

```bash
sed -i 's|zigbee2mqtt:2.12.0|zigbee2mqtt:2.7|' docker-compose.yaml
docker compose pull zigbee2mqtt
docker compose up -d zigbee2mqtt
docker compose logs -f zigbee2mqtt
```

---

## Restore HA Postgres from backup

> HA config (automations, scripts) lives on NAS (`ha_data` volume) — survives restarts.  
> This restore is only needed if the recorder DB (history/stats) is corrupt.

```bash
docker compose exec ha-postgres-backup ls -lh /backups/

docker compose stop homeassistant
docker compose exec ha-postgres-backup /scripts/restore_db.sh /backups/home-assistant_db_YYYY-MM-DD_HH-MM-SS.dump
docker compose start homeassistant
```

---

## Zigbee devices not responding

```bash
# Check USB stick is visible:
ls -la /dev/ttyUSB0

# If missing: physically reseat the stick, then:
docker compose restart zigbee2mqtt
docker compose logs --tail=30 zigbee2mqtt
```

---

## Verify

```bash
docker compose ps
curl -sf http://localhost:8123 && echo OK
```
