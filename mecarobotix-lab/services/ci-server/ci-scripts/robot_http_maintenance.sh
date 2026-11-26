#!/bin/bash
set -eu
set -x

# shellcheck source=ci-secrets.env
. /opt/mecarobotix-ci/ci-secrets.env

ROBOT_HOST="${ROBOT_HOST:-robot-a-01}"
ROBOT_PATH="${ROBOT_PATH:-status}"
EXTRA_SH="${EXTRA_SH:-}"

robot_api_key() {
  case "${ROBOT_HOST}" in
    *robot-b*) printf '%s' "${ROBOT_B_API_KEY}" ;;
    *) printf '%s' "${ROBOT_A_API_KEY}" ;;
  esac
}

client_tls_args() {
  if [ -n "${CLIENT_TLS_CERT_FILE:-}" ] && [ -n "${CLIENT_TLS_KEY_FILE:-}" ] \
    && [ -r "${CLIENT_TLS_CERT_FILE}" ] && [ -r "${CLIENT_TLS_KEY_FILE}" ]; then
    printf '%s\n' "--cert" "${CLIENT_TLS_CERT_FILE}" "--key" "${CLIENT_TLS_KEY_FILE}"
  fi
}

URL="https://${ROBOT_HOST}:8443/${ROBOT_PATH}"

echo "[CI] Running HTTPS robot maintenance with header-based credentials"
echo "[CI] URL=${URL}"
set +x
curl -s -H "X-Robot-Api-Key: $(robot_api_key)" -H "X-Jenkins-Token: ${JENKINS_API_TOKEN}" $(client_tls_args) "${URL}" \
  | tee /tmp/robot-maintenance-response.json
set -x

echo "[CI] Querying diagnostic-server with header-based credentials"
set +x
curl -s -H "X-Gitea-Password: ${GITEA_PASSWORD}" -H "X-Jenkins-Password: ${JENKINS_ADMIN_PASSWORD}" $(client_tls_args) "${DIAGNOSTIC_URL}/api/lab/config" \
  | tee /tmp/diagnostic-config-response.json
set -x

if [ -n "${EXTRA_SH}" ]; then
  echo "[CI] Executing unvalidated shell parameter: ${EXTRA_SH}"
  sh -c "${EXTRA_SH}"
fi
