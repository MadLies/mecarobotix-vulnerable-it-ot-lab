#!/bin/sh
set -eu

ENV_FILE="${ENV_FILE:-.env}"
JENKINS_TOKEN="${JENKINS_API_TOKEN:-$(openssl rand -hex 24)}"

if [ ! -f "$ENV_FILE" ]; then
  echo "[!] Missing env file: $ENV_FILE" >&2
  exit 1
fi

update_or_append() {
  key="$1"
  value="$2"

  if grep -q "^${key}=" "$ENV_FILE"; then
    tmp_file="$(mktemp)"
    sed "s|^${key}=.*|${key}=${value}|" "$ENV_FILE" > "$tmp_file"
    cat "$tmp_file" > "$ENV_FILE"
    rm -f "$tmp_file"
  else
    printf '\n%s=%s\n' "$key" "$value" >> "$ENV_FILE"
  fi
}

update_or_append "JENKINS_API_TOKEN" "$JENKINS_TOKEN"

echo "[+] Rotated JENKINS_API_TOKEN in $ENV_FILE"
echo "[!] Recreate ci-server to apply the new runtime token."
