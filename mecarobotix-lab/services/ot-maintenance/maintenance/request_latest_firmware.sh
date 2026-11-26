#!/bin/bash
set -e

# shellcheck source=lib/common.sh
. /opt/maintenance/lib/common.sh

ROBOT_TYPE=${1:-A}
URL="${DIAGNOSTIC_URL}/api/firmware/latest?robot_type=${ROBOT_TYPE}"

safe_get "${URL}" | jq . 2>/dev/null || safe_get "${URL}"
