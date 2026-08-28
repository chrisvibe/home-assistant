# Home Assistant — Emergency Runbook

**Current versions:** HA 2026.7.4 · Postgres 16-alpine  
**Previous versions:** HA 2026.7.2

> Zigbee2MQTT and the MQTT broker moved to their own compose project on
> 2026-08-28. For anything about the mesh, the broker, or restoring Zigbee
> state, see `../zigbee/EMERGENCY.md` — and run those commands from
> `~/self-hosting/services/zigbee`, not from here.

---

## Quick check

```bash
docker compose ps
curl -sf http://localhost:8123 && echo OK
docker compose logs --tail=30 homeassistant
```

Containers: `homeassistant` · `ha-postgres` · `ha-postgres-backup`

**Where the data lives** (matters when the NAS is down):

| What | Where | Survives elephant being off? |
|---|---|---|
| HA config `/config` | NFS on elephant | no — HA will not start |
| HA recorder DB | local disk (`home-assistant_ha_pg_data`) | yes |
| all backups | NFS on elephant | no — sidecars fail to start, nothing else affected |

So with the NAS down, **Home Assistant does not start, and the Zigbee mesh keeps
working anyway** — that separation is the entire point of the two projects.
The backup sidecars will restart-loop until the NAS is back; expected, harmless.

---

## Rollback Home Assistant

```bash
git log --oneline -5 docker-compose.yaml

sed -i 's|home-assistant:2026.7.4|home-assistant:2026.7.2|' docker-compose.yaml
docker compose pull homeassistant
docker compose up -d homeassistant
docker compose logs -f homeassistant
```

---

## Restore HA Postgres from backup

> HA config (automations, scripts) lives on the NAS (`ha_data` volume) and
> survives restarts. This restore is only needed if the recorder DB
> (history/stats) is corrupt.

```bash
docker compose exec ha-postgres-backup ls -lh /backups/

docker compose stop homeassistant
docker compose exec ha-postgres-backup /scripts/restore_db.sh /backups/home-assistant_db_YYYY-MM-DD_HH-MM-SS.dump
docker compose start homeassistant
```

---

## Home Assistant cannot reach MQTT

HA resolves the broker as `mqtt` over the external `mesh` network. Both
containers must be attached to it:

```bash
docker network inspect mesh --format '{{range .Containers}}{{.Name}} {{end}}'
docker exec homeassistant getent hosts mqtt
```

If `mesh` is missing, recreate it and bring both projects back up:

```bash
docker network create mesh
docker compose up -d                                  # from services/home-assistant
docker compose up -d                                  # and from services/zigbee
```

---

## Verify

```bash
docker compose ps
curl -sf http://localhost:8123 && echo OK
```
