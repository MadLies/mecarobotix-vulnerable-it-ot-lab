#!/bin/bash
set -euo pipefail

SENSITIVE_DIR="/seed/sensitive-files"
POSTGRES_HOST="${POSTGRES_HOST:-}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"

psql_db() {
  if [ -n "$POSTGRES_HOST" ]; then
    psql -v ON_ERROR_STOP=1 --host "$POSTGRES_HOST" --port "$POSTGRES_PORT" --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" "$@"
  else
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" "$@"
  fi
}

if [ -n "$POSTGRES_HOST" ]; then
  echo "[+] Waiting for PostgreSQL at $POSTGRES_HOST:$POSTGRES_PORT..."
  until pg_isready --host "$POSTGRES_HOST" --port "$POSTGRES_PORT" --username "$POSTGRES_USER" --dbname "$POSTGRES_DB"; do
    sleep 2
  done
fi

psql_db <<'SQL'
CREATE SCHEMA IF NOT EXISTS lab;

CREATE TABLE IF NOT EXISTS lab."sensitive information" (
    id SERIAL PRIMARY KEY,
    file_name TEXT NOT NULL UNIQUE,
    file_weight_bytes BIGINT NOT NULL,
    file_sha256 TEXT NOT NULL,
    file_content BYTEA NOT NULL,
    loaded_at TIMESTAMP DEFAULT NOW()
);
SQL

if [ ! -d "$SENSITIVE_DIR" ]; then
  echo "[!] Sensitive files directory not found: $SENSITIVE_DIR"
  exit 0
fi

for FILE_PATH in "$SENSITIVE_DIR"/*; do
  [ -f "$FILE_PATH" ] || continue

  FILE_NAME="$(basename "$FILE_PATH")"
  FILE_WEIGHT="$(wc -c < "$FILE_PATH" | tr -d ' ')"
  FILE_SHA256="$(sha256sum "$FILE_PATH" | awk '{print $1}')"
  FILE_HEX="$(od -An -tx1 -v "$FILE_PATH" | tr -d ' \n')"
  SQL_FILE_NAME="$(printf '%s' "$FILE_NAME" | sed "s/'/''/g")"

  echo "[+] Loading sensitive file into PostgreSQL: $FILE_NAME"

  psql_db <<SQL
INSERT INTO lab."sensitive information" (
    file_name,
    file_weight_bytes,
    file_sha256,
    file_content
) VALUES (
    '$SQL_FILE_NAME',
    $FILE_WEIGHT,
    '$FILE_SHA256',
    decode('$FILE_HEX', 'hex')
)
ON CONFLICT (file_name) DO UPDATE SET
    file_weight_bytes = EXCLUDED.file_weight_bytes,
    file_sha256 = EXCLUDED.file_sha256,
    file_content = EXCLUDED.file_content,
    loaded_at = NOW();
SQL
done
