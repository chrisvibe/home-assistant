#!/bin/sh
# Long-running backup-sidecar entrypoint. Kept deliberately IDENTICAL in shape to the
# one in the Postgres services (services/*/scripts/backup-entrypoint.sh) -- the only
# difference is the base image this runs on. Installs dcron, schedules backup.sh per
# $BACKUP_CRON_SCHEDULE, runs one backup immediately at startup (so a fresh deploy
# produces a backup and surfaces errors now), then hands off to crond in the foreground.
set -eu

SCHEDULE="${BACKUP_CRON_SCHEDULE:-20 3 * * *}"
RETENTION="${BACKUP_RETENTION_DAYS:-30}"
SERVICE_NAME="${SERVICE_NAME:-zigbee2mqtt}"

echo "[entrypoint] service=${SERVICE_NAME} schedule='${SCHEDULE}' retention=${RETENTION}d"

# dcron isn't in the alpine base image; install it. (The Postgres sidecars do the same
# thing for the same reason -- postgres:*-alpine doesn't ship it either.)
echo "[entrypoint] installing dcron..."
apk add --no-cache dcron >/dev/null

# Crontab runs the per-service orchestrator and appends to a log on the backup volume.
echo "${SCHEDULE} /scripts/backup.sh >> /backups/backup.log 2>&1" > /etc/crontabs/root

# Run once now. Guarded so a failed first run still lets crond start and retry on schedule.
# This matters more here than for the DB sidecars: /backups is NFS on elephant, so a
# NAS outage makes the initial backup fail, and that must not turn into a restart loop.
echo "[entrypoint] running initial backup..."
/scripts/backup.sh || echo "[entrypoint] WARNING: initial backup failed (see above); crond will retry"

# Run crond in the foreground as a CHILD of this shell (PID 1), not via exec.
# As PID 1, crond is a session leader and its setpgid() call fails with EPERM,
# making it exit immediately -> container restart loop. As a child it's fine.
echo "[entrypoint] starting crond (foreground)..."
crond -f -l 2
