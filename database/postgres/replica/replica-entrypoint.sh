#!/bin/sh
set -e

if [ ! -s "$PGDATA/PG_VERSION" ]; then
  echo "[replica] esperando a postgres-primary..."
  until pg_isready -h "$PRIMARY_HOST" -p "$PRIMARY_PORT" -U "$POSTGRES_USER"; do
    sleep 2
  done

  echo "[replica] inicializando replica desde backup base..."
  rm -rf "$PGDATA"/*
  export PGPASSWORD="$REPLICATION_PASSWORD"
  pg_basebackup \
    -h "$PRIMARY_HOST" \
    -p "$PRIMARY_PORT" \
    -D "$PGDATA" \
    -U "$REPLICATION_USER" \
    -Fp \
    -Xs \
    -P \
    -R
  chmod 700 "$PGDATA"
fi

exec docker-entrypoint.sh postgres -c hot_standby=on
