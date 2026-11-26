#!/bin/bash
set -euo pipefail
BACKUP_DIR="./backups/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

echo "[+] Saving project files"
tar -czf "$BACKUP_DIR/project_files.tar.gz" \
  docker-compose.yml .env configs services data scripts docs README.md 2>/dev/null || true

echo "[+] Saving Docker volumes for this compose project"
for volume in $(docker volume ls -q | grep '^mecarobotix' || true); do
  echo "    - $volume"
  docker run --rm \
    -v "$volume:/volume" \
    -v "$PWD/$BACKUP_DIR:/backup" \
    alpine \
    tar -czf "/backup/${volume}.tar.gz" -C /volume .
done

echo "[+] Backup completed in $BACKUP_DIR"
