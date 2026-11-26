#!/bin/bash
set -e

# shellcheck source=lib/common.sh
. /opt/maintenance/lib/common.sh

ROBOT_HOST=${1:-${DEFAULT_ROBOT_HOST:-robot-a-01}}
OUT="${BACKUP_DIR}/${ROBOT_HOST}-debug-config-$(date -u +%Y%m%d%H%M%S).json"
URL="$(robot_url "${ROBOT_HOST}")/debug/config"

log_line "collecting robot debug config from ${URL} into ${OUT}"
safe_get "${URL}" -H "X-Postgres-Password: ${POSTGRES_PASSWORD}" > "${OUT}"
chmod 0666 "${OUT}"
printf '%s\n' "${OUT}"
