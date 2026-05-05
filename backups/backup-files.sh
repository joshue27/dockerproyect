#!/bin/sh
set -eu

backup_dir="/backups/files"
source_dir="${FILES_SOURCE_PATH:-/source}"
archive_prefix="${FILES_ARCHIVE_PREFIX:-app-files}"

mkdir -p "$backup_dir"

while true; do
  timestamp=$(date +%Y%m%d_%H%M%S)
  file="$backup_dir/${archive_prefix}_${timestamp}.tar.gz"

  echo "[backup-files] empaquetando archivos desde $source_dir en $file"
  tar -czf "$file" -C "$source_dir" .

  find "$backup_dir" -type f -name '*.tar.gz' -mtime +"${FILES_BACKUP_RETENTION_DAYS}" -delete

  echo "[backup-files] respaldo completado; siguiente corrida en ${FILES_BACKUP_INTERVAL_SECONDS}s"
  sleep "$FILES_BACKUP_INTERVAL_SECONDS"
done
