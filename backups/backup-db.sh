#!/bin/sh
set -eu

backup_dir="/backups/db"
mkdir -p "$backup_dir"

while true; do
  timestamp=$(date +%Y%m%d_%H%M%S)
  file="$backup_dir/${POSTGRES_DB}_${timestamp}.sql.gz"

  echo "[backup-db] esperando disponibilidad de PostgreSQL..."
  until pg_isready -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB"; do
    sleep 2
  done

  echo "[backup-db] generando respaldo en $file"
  pg_dump \
    -h "$POSTGRES_HOST" \
    -p "$POSTGRES_PORT" \
    -U "$POSTGRES_USER" \
    -d "$POSTGRES_DB" | gzip > "$file"

  find "$backup_dir" -type f -name '*.sql.gz' -mtime +"${DB_BACKUP_RETENTION_DAYS}" -delete

  echo "[backup-db] respaldo completado; siguiente corrida en ${DB_BACKUP_INTERVAL_SECONDS}s"
  sleep "$DB_BACKUP_INTERVAL_SECONDS"
done
