#!/usr/bin/env bash
# Compressed, integrity-verified Minecraft world & config backup script.
# Usage: backup.sh [scheduled|manual|pre-upgrade|pre-mod-change]

set -euo pipefail

MC_DIR="/home/ec2-user/minecraft"
BACKUP_DIR="${MC_DIR}/backups"
MC_CMD="${MC_DIR}/scripts/mc-cmd.sh"
REASON="${1:-scheduled}"
RETENTION_SCHEDULED="${RETENTION_SCHEDULED:-7}"
STAMP="$(date -u '+%Y%m%d-%H%M%SZ')"
ARCHIVE_NAME="mc-backup-${REASON}-${STAMP}.tar.zst"
ARCHIVE_PATH="${BACKUP_DIR}/${ARCHIVE_NAME}"
TMP_ARCHIVE="${ARCHIVE_PATH}.partial"

mkdir -p "$BACKUP_DIR"

SAVE_PAUSED=0
cleanup() {
  local rc=$?
  if [[ "$SAVE_PAUSED" -eq 1 && -x "$MC_CMD" ]]; then
    "$MC_CMD" "save-on" || true
  fi
  rm -f "$TMP_ARCHIVE"
  exit "$rc"
}
trap cleanup EXIT

echo "[$(date -Is)] Starting ${REASON} backup -> ${ARCHIVE_NAME}"

# Check free space (require >= 2 GiB free)
FREE_KB=$(df -Pk "$BACKUP_DIR" | awk 'NR==2 {print $4}')
if (( FREE_KB < 2097152 )); then
  echo "[ERROR] Less than 2 GiB free on disk (${FREE_KB} KiB). Aborting backup." >&2
  exit 1
fi

if systemctl is-active --quiet minecraft.service && [[ -p "${MC_DIR}/run/console.fifo" ]]; then
  echo "[$(date -Is)] Server is running; pausing chunk writes and flushing world..."
  "$MC_CMD" "save-off"
  SAVE_PAUSED=1
  "$MC_CMD" "save-all flush"
  sleep 4
fi

# Include world, server configs, player lists, and mod manifest (skip huge caches/logs/backups)
INCLUDE_ITEMS=()
for item in world server.properties ops.json whitelist.json banned-ips.json banned-players.json config jvm.conf mods_manifest.json; do
  if [[ -e "${MC_DIR}/${item}" ]]; then
    INCLUDE_ITEMS+=("$item")
  fi
done

tar -C "$MC_DIR" -cf - "${INCLUDE_ITEMS[@]}" | zstd -T2 -6 -q -o "$TMP_ARCHIVE"

if [[ "$SAVE_PAUSED" -eq 1 ]]; then
  "$MC_CMD" "save-on"
  SAVE_PAUSED=0
fi

# Verify archive integrity before finalizing
zstd -t "$TMP_ARCHIVE"
tar --use-compress-program=zstd -tf "$TMP_ARCHIVE" > /dev/null

mv "$TMP_ARCHIVE" "$ARCHIVE_PATH"
(
  cd "$BACKUP_DIR"
  sha256sum "$ARCHIVE_NAME" > "${ARCHIVE_NAME}.sha256"
)

SIZE_H=$(du -h "$ARCHIVE_PATH" | awk '{print $1}')
echo "[$(date -Is)] Backup verified: ${ARCHIVE_NAME} (${SIZE_H})"

# Prune old scheduled backups only (preserve manual/pre-* safety backups)
if [[ "$REASON" == "scheduled" ]]; then
  mapfile -t OLD_SCHED < <(ls -1t "${BACKUP_DIR}"/mc-backup-scheduled-*.tar.zst 2>/dev/null | tail -n +"$((RETENTION_SCHEDULED + 1))" || true)
  for old in "${OLD_SCHED[@]}"; do
    echo "[$(date -Is)] Pruning old scheduled backup: $(basename "$old")"
    rm -f "$old" "${old}.sha256"
  done
fi
