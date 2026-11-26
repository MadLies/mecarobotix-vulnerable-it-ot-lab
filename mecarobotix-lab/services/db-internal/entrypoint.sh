#!/bin/bash
set -euo pipefail

TLS_SRC_DIR="${POSTGRES_TLS_SRC_DIR:-/etc/mecarobotix/tls}"
TLS_RUNTIME_DIR="${POSTGRES_TLS_RUNTIME_DIR:-/var/lib/postgresql/tls}"

if [ -f "${TLS_SRC_DIR}/tls-chain.crt" ] && [ -f "${TLS_SRC_DIR}/tls.key" ]; then
  mkdir -p "$TLS_RUNTIME_DIR"
  cp "${TLS_SRC_DIR}/tls-chain.crt" "${TLS_RUNTIME_DIR}/server.crt"
  cp "${TLS_SRC_DIR}/tls.key" "${TLS_RUNTIME_DIR}/server.key"
  chown -R postgres:postgres "$TLS_RUNTIME_DIR"
  chmod 0750 "$TLS_RUNTIME_DIR"
  chmod 0644 "${TLS_RUNTIME_DIR}/server.crt"
  chmod 0600 "${TLS_RUNTIME_DIR}/server.key"
fi

exec /usr/local/bin/docker-entrypoint.sh "$@"
