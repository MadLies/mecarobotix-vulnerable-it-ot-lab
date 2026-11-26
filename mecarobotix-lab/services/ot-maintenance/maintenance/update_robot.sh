#!/bin/bash
set -e

# shellcheck source=lib/common.sh
. /opt/maintenance/lib/common.sh

ROBOT_HOST=${1:-${DEFAULT_ROBOT_HOST:-robot-a-01}}
URL="$(robot_url "${ROBOT_HOST}")/update-firmware"

safe_get "${URL}" | jq . 2>/dev/null || safe_get "${URL}"
