#!/bin/sh
# Zigbee2MQTT state backup -> timestamped tar.gz on the NAS.
#
# WHY THIS EXISTS AT ALL: until 2026-08-24 zigbee2mqtt had NO backup. A volume named
# ha_zigbee2mqtt_backups was declared in the compose file but no service ever mounted it,
# so Docker never created it and the NAS directory sat empty from March onwards.
#
# WHAT IS IN HERE AND WHY IT MATTERS MORE THAN THE RECORDER DB: coordinator_backup.json
# holds the Zigbee network key and PAN ID, database.db holds the device registry. Losing
# those means re-pairing every device in the house by hand (see notes.txt for what that
# involves per device). Losing the HA recorder dump only costs history.
#
# The whole of /data is ~50 KB with the rotating logs excluded, so this takes a full copy
# every run -- nothing incremental to go wrong.
set -eu

BACKUP_DIR="${BACKUP_DIR:-/backups}"
DATA_DIR="${DATA_DIR:-/data}"
RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"
SERVICE_NAME="${SERVICE_NAME:-zigbee2mqtt}"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

mkdir -p "$BACKUP_DIR"
TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)
BACKUP_FILE="${BACKUP_DIR}/${SERVICE_NAME}_state_${TIMESTAMP}.tar.gz"

# Refuse to write a backup that is missing the thing worth backing up. Without this a
# broken mount or an empty volume would quietly produce a valid-looking tarball every
# night and roll the good ones out via retention.
if [ ! -f "${DATA_DIR}/database.db" ]; then
    log "ERROR: ${DATA_DIR}/database.db not found - refusing to write an empty backup"
    exit 1
fi

log "Backing up ${DATA_DIR} -> ${BACKUP_FILE}"

# Write to a .tmp first, then atomically rename. A crashed/partial run never gets the
# final name, so it can't masquerade as a good backup. Same rule as backup_db.sh.
# ./log is excluded: rotating zigbee2mqtt logs, worthless to restore and far larger
# than the state we actually care about. The .pre-restore-*.tar.gz snapshots that
# restore.sh leaves behind are excluded too -- without that, every restore would bake
# its snapshot into all future backups, and backups would nest inside backups forever.
tar czf "${BACKUP_FILE}.tmp" -C "$DATA_DIR" \
    --exclude=./log \
    --exclude='./.pre-restore-*.tar.gz' \
    .
mv "${BACKUP_FILE}.tmp" "$BACKUP_FILE"

log "Backup OK: ${BACKUP_FILE} ($(du -h "$BACKUP_FILE" | cut -f1))"

# Retention: delete backups older than N days (only fully-named .tar.gz files qualify).
DELETED=$(find "$BACKUP_DIR" -name "${SERVICE_NAME}_state_*.tar.gz" -type f -mtime "+${RETENTION_DAYS}" -print -delete | wc -l)
REMAINING=$(find "$BACKUP_DIR" -name "${SERVICE_NAME}_state_*.tar.gz" -type f | wc -l)
log "Retention ${RETENTION_DAYS}d: pruned ${DELETED}, ${REMAINING} backup(s) remain"
