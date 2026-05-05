#!/bin/sh
set -eu

mode="${RCLONE_SYNC_MODE:-copy}"
remote_name="${RCLONE_REMOTE_NAME:-gdrive}"
remote_path="${RCLONE_REMOTE_PATH:-sistemaventas/backups}"
source_dir="/backups"
target="${remote_name}:${remote_path}"

case "$mode" in
  copy|sync) ;;
  *)
    echo "[rclone-sync] modo invalido: $mode. Usa 'copy' o 'sync'."
    exit 1
    ;;
esac

while true; do
  echo "[rclone-sync] ejecutando '$mode' hacia $target"
  rclone "$mode" "$source_dir" "$target" --config /config/rclone/rclone.conf --create-empty-src-dirs
  echo "[rclone-sync] sincronizacion completada; siguiente corrida en ${RCLONE_SYNC_INTERVAL_SECONDS}s"
  sleep "$RCLONE_SYNC_INTERVAL_SECONDS"
done
