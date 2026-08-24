# Home Assistant — Emergency Runbook

**Current versions:** HA 2026.7.4 · Zigbee2MQTT 2.12.1 · Mosquitto 2.0.22 · Postgres 16-alpine  
**Previous versions:** HA 2026.7.2 · Zigbee2MQTT 2.12.0

---

## Quick check

```bash
docker compose ps
curl -sf http://localhost:8123 && echo OK
docker compose logs --tail=30 homeassistant
```

Containers: `homeassistant` · `ha-postgres` · `ha-postgres-backup` · `zigbee2mqtt` · `zigbee2mqtt-backup` · `mqtt`

**Where the data lives** (matters when the NAS is down):

| What | Where | Survives elephant being off? |
|---|---|---|
| HA config `/config` | NFS on elephant | no — HA will not start |
| HA recorder DB | local disk (`home-assistant_ha_pg_data`) | yes |
| Zigbee state `/app/data` | local disk (`zigbee2mqtt_data`) | yes |
| all backups | NFS on elephant | no — sidecars fail to start, nothing else affected |

So with the NAS down, **Zigbee and the lights keep working and Home Assistant does not.**
The backup sidecars will restart-loop until the NAS is back; that is expected and harmless.

---

## Rollback Home Assistant

```bash
git log --oneline -5 docker-compose.yaml

sed -i 's|home-assistant:2026.7.2|home-assistant:2026.6.4|' docker-compose.yaml
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

## Restore Zigbee2MQTT state from backup

> `coordinator_backup.json` (network key + PAN) and `database.db` (device registry).
> Losing these means re-pairing every device by hand — this is the one to get right.
> Backups are nightly tar.gz on the NAS, named `zigbee2mqtt_state_*.tar.gz`.

```bash
docker compose exec zigbee2mqtt-backup ls -lh /backups/

# STOP z2m first — it rewrites database.db and would overwrite the restore.
docker compose stop zigbee2mqtt

docker run --rm \
    -v zigbee2mqtt_data:/data \
    -v zigbee2mqtt_backups:/backups:ro \
    -v "$PWD/zigbee2mqtt/scripts:/scripts:ro" \
    alpine:3.22 sh /scripts/restore.sh /backups/zigbee2mqtt_state_YYYY-MM-DD_HH-MM-SS.tar.gz

docker compose start zigbee2mqtt
```

The restore snapshots the current state to `/data/.pre-restore-<timestamp>.tar.gz` first,
so restoring from the wrong file is itself undoable.

Back up right now, off-schedule:

```bash
docker compose exec zigbee2mqtt-backup /scripts/backup.sh
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
