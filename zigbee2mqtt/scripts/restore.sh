#!/bin/sh
# Restore Zigbee2MQTT state from a tar.gz produced by backup.sh.
#
# This is NOT run inside the zigbee2mqtt-backup sidecar: that container mounts /data
# read-only on purpose, so a backup process can never corrupt what it is backing up.
# A restore is a deliberate one-off. From services/home-assistant/ on elis:
#
#   docker compose stop zigbee2mqtt
#   docker run --rm \
#       -v zigbee2mqtt_data:/data \
#       -v zigbee2mqtt_backups:/backups:ro \
#       -v "$PWD/zigbee2mqtt/scripts:/scripts:ro" \
#       alpine:3.22 sh /scripts/restore.sh /backups/zigbee2mqtt_state_YYYY-MM-DD_HH-MM-SS.tar.gz
#   docker compose start zigbee2mqtt
#
# ORDER MATTERS: zigbee2mqtt must be STOPPED first. It holds database.db open and
# rewrites it periodically, so a restore underneath a running instance is overwritten
# again within a minute or two and you would be left wondering why it "didn't take".
#
# Set FORCE=1 (or pass --force) to skip the interactive confirmation.
set -eu

BACKUP_FILE="${1:-}"
FORCE="${FORCE:-0}"
[ "${2:-}" = "--force" ] && FORCE=1

DATA_DIR="${DATA_DIR:-/data}"
BACKUP_DIR="${BACKUP_DIR:-/backups}"
SERVICE_NAME="${SERVICE_NAME:-zigbee2mqtt}"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

if [ -z "$BACKUP_FILE" ]; then
    echo "Usage: $0 <backup_file.tar.gz>"
    echo "Available backups:"
    ls -lh "${BACKUP_DIR}/${SERVICE_NAME}_state_"*.tar.gz 2>/dev/null || echo "  (none found)"
    exit 1
fi
[ -f "$BACKUP_FILE" ] || { echo "ERROR: not found: $BACKUP_FILE"; exit 1; }

# Fail fast if /data is read-only, rather than half-way through the extract.
if ! touch "${DATA_DIR}/.restore-write-test" 2>/dev/null; then
    echo "ERROR: ${DATA_DIR} is not writable."
    echo "You are probably running this inside the zigbee2mqtt-backup sidecar, which"
    echo "mounts /data read-only. Use the one-off 'docker run' at the top of this file."
    exit 1
fi
rm -f "${DATA_DIR}/.restore-write-test"

# Validate the archive BEFORE touching anything that is currently working.
if ! tar tzf "$BACKUP_FILE" >/dev/null 2>&1; then
    echo "ERROR: '$BACKUP_FILE' is not a readable tar.gz (corrupt or truncated)."
    exit 1
fi
if ! tar tzf "$BACKUP_FILE" | grep -q '^\./database\.db$'; then
    echo "ERROR: '$BACKUP_FILE' contains no ./database.db - refusing to restore from it."
    exit 1
fi

echo "=========================================="
echo " RESTORE  zigbee2mqtt state -> ${DATA_DIR}"
echo " from     ${BACKUP_FILE}"
echo "=========================================="
if [ "$FORCE" != "1" ]; then
    echo "WARNING: this overwrites the live Zigbee network state (device registry,"
    echo "network key). Make sure the zigbee2mqtt container is STOPPED."
    printf "Type 'yes' to proceed: "
    read -r CONFIRM
    [ "$CONFIRM" = "yes" ] || { echo "Cancelled."; exit 0; }
fi

# Snapshot what is there now, so a restore from the wrong file is itself undoable.
# Dot-prefixed and excluded by backup.sh so it never nests inside future backups.
SNAPSHOT="${DATA_DIR}/.pre-restore-$(date +%Y-%m-%d_%H-%M-%S).tar.gz"
log "Snapshotting current state -> ${SNAPSHOT}"
tar czf "$SNAPSHOT" -C "$DATA_DIR" \
    --exclude=./log \
    --exclude='./.pre-restore-*.tar.gz' \
    .

log "Extracting..."
tar xzf "$BACKUP_FILE" -C "$DATA_DIR"

log "Restore complete. Start zigbee2mqtt and check the device list in the frontend."
log "If it looks wrong, the previous state is in ${SNAPSHOT}"
