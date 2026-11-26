#!/bin/sh
set -eu

name="${1:-}"
PKI_DIR="${PKI_DIR:-data/pki}"
REVOCATION_FILE="${PKI_DIR}/revoked-clients.txt"

case "$name" in
  ""|*[^A-Za-z0-9._-]*)
    echo "Usage: $0 <client-cn>" >&2
    echo "Example: $0 ci-server" >&2
    exit 1
    ;;
esac

mkdir -p "$PKI_DIR"
touch "$REVOCATION_FILE"

if grep -qxF "$name" "$REVOCATION_FILE"; then
  echo "[=] Client CN already revoked: ${name}"
  exit 0
fi

printf '%s\n' "$name" >> "$REVOCATION_FILE"
chmod 0644 "$REVOCATION_FILE"

echo "[+] Revoked client CN: ${name}"
echo "[!] Restart/recreate services that mount the revocation file if they need a fresh readonly bind mount."
