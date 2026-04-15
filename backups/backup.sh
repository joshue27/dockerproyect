#!/bin/sh
set -e

mkdir -p /backups

while true; do
  timestamp=$(date +%Y%m%d_%H%M%S)
  file="/backups/${POSTGRES_DB}_${timestamp}.sql.gz"

  echo "[backup] esperando disponibilidad de PostgreSQL..."
  until pg_isready -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB"; do
    sleep 2
  done

  echo "[backup] generando respaldo en $file"
  pg_dump \
    -h "$POSTGRES_HOST" \
    -p "$POSTGRES_PORT" \
    -U "$POSTGRES_USER" \
    -d "$POSTGRES_DB" | gzip > "$file"

  find /backups -type f -name '*.sql.gz' -mtime +"$BACKUP_RETENTION_DAYS" -delete

  echo "[backup] respaldo completado; siguiente corrida en ${BACKUP_INTERVAL_SECONDS}s"
  sleep "$BACKUP_INTERVAL_SECONDS"
done
