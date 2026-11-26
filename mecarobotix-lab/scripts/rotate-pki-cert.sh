#!/bin/sh
set -eu

usage() {
  echo "Usage: $0 <service|client> <name>" >&2
  echo "Example: $0 client ci-server" >&2
  echo "Example: $0 service diagnostic-server" >&2
}

safe_name() {
  case "$1" in
    ""|*[^A-Za-z0-9._-]*)
      echo "[!] Invalid certificate name: $1" >&2
      exit 1
      ;;
  esac
}

kind="${1:-}"
name="${2:-}"

if [ -z "$kind" ] || [ -z "$name" ]; then
  usage
  exit 1
fi

safe_name "$name"

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PKI_DIR="${PKI_DIR:-data/pki}"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"

case "$kind" in
  service)
    cert_dir="${PKI_DIR}/services/${name}"
    files="tls.key tls.csr tls.crt tls-chain.crt san.cnf"
    ;;
  client)
    cert_dir="${PKI_DIR}/clients/${name}"
    files="client.key client.csr client.crt client-chain.crt client.cnf"
    ;;
  *)
    usage
    exit 1
    ;;
esac

archive_dir="${PKI_DIR}/rotated/${kind}s/${name}/${timestamp}"
mkdir -p "$archive_dir" "$cert_dir"

found=0
for file in $files; do
  if [ -e "${cert_dir}/${file}" ]; then
    mv "${cert_dir}/${file}" "${archive_dir}/${file}"
    found=1
  fi
done

if [ "$found" = "1" ]; then
  echo "[+] Archived previous ${kind} certificate material in ${archive_dir}"
else
  echo "[=] No existing ${kind} certificate material found for ${name}; generating it"
fi

PKI_DIR="$PKI_DIR" "$SCRIPT_DIR/generate-pki.sh"

echo "[+] Rotated ${kind} certificate for ${name}"
echo "[!] Restart or recreate services using this certificate so they reload the new files."
