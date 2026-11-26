#!/bin/bash
set -e

# shellcheck source=lib/common.sh
. /opt/maintenance/lib/common.sh

for robot in ${ROBOT_LIST}; do
  log_line "checking status for ${robot}"
  /opt/maintenance/check_status.sh "${robot}" || true
  printf '\n'
done
