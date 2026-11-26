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

tmp="${REVOCATION_FILE}.tmp.$$"
grep -vxF "$name" "$REVOCATION_FILE" > "$tmp" || true
mv "$tmp" "$REVOCATION_FILE"
chmod 0644 "$REVOCATION_FILE"

echo "[+] Removed client CN from revocation registry: ${name}"
