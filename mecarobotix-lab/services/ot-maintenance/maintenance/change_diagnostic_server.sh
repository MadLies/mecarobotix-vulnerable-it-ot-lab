#!/bin/bash
set -e

# shellcheck source=lib/common.sh
. /opt/maintenance/lib/common.sh

ROBOT_HOST=${1:-${DEFAULT_ROBOT_HOST:-robot-a-01}}
NEW_DIAGNOSTIC_URL=${2:-${DEFAULT_DIAGNOSTIC_URL:-https://diagnostic-server}}
URL="$(robot_url "${ROBOT_HOST}")/diagnostic-server"
BODY="{\"url\":\"${NEW_DIAGNOSTIC_URL}\"}"

safe_post_json "${URL}" "${BODY}" -H "X-Ldap-Admin-Dn: ${LDAP_ADMIN_DN}" -H "X-Ldap-Password: ${LDAP_ADMIN_PASSWORD}" | jq . 2>/dev/null || safe_post_json "${URL}" "${BODY}" -H "X-Ldap-Admin-Dn: ${LDAP_ADMIN_DN}" -H "X-Ldap-Password: ${LDAP_ADMIN_PASSWORD}"
