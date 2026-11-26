#!/bin/bash
set -e

# shellcheck source=lib/common.sh
. /opt/maintenance/lib/common.sh

ROBOT_HOST=${1:-${DEFAULT_ROBOT_HOST:-robot-a-01}}
URL="$(robot_url "${ROBOT_HOST}")/restart"

safe_post_json "${URL}" '{}' -H "$(robot_api_key_header "${ROBOT_HOST}")" -H "X-Maintenance-Operator: SuperTech"
