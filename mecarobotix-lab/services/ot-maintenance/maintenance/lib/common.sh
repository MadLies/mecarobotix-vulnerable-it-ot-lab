#!/bin/bash

MAINTENANCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="${LOG_DIR:-/var/log/ot-maintenance}"
BACKUP_DIR="${BACKUP_DIR:-${MAINTENANCE_ROOT}/backups}"

set -a
if [ -f "${MAINTENANCE_ROOT}/config/robots.env" ]; then
  # shellcheck disable=SC1091
  . "${MAINTENANCE_ROOT}/config/robots.env"
fi
if [ -f "${MAINTENANCE_ROOT}/config/secrets.env" ]; then
  # shellcheck disable=SC1091
  . "${MAINTENANCE_ROOT}/config/secrets.env"
fi
set +a

mkdir -p "${LOG_DIR}" "${BACKUP_DIR}"

timestamp() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

log_line() {
  printf '[%s] %s\n' "$(timestamp)" "$*" | tee -a "${LOG_DIR}/operations.log" >&2
}

robot_url() {
  local robot_host="${1:-${DEFAULT_ROBOT_HOST:-robot-a-01}}"

  case "${robot_host}" in
    robot-a-01)
      printf '%s' "${ROBOT_A_01_URL:-https://robot-a-01:8443}"
      ;;
    robot-a-02)
      printf '%s' "${ROBOT_A_02_URL:-https://robot-a-02:8443}"
      ;;
    robot-b-01)
      printf '%s' "${ROBOT_B_01_URL:-https://robot-b-01:8443}"
      ;;
    *)
      printf 'https://%s:%s' "${robot_host}" "${ROBOT_HTTPS_PORT:-8443}"
      ;;
  esac
}

robot_api_key() {
  local robot_host="${1:-${DEFAULT_ROBOT_HOST:-robot-a-01}}"

  case "${robot_host}" in
    *robot-b*)
      printf '%s' "${ROBOT_B_API_KEY}"
      ;;
    *)
      printf '%s' "${ROBOT_A_API_KEY}"
      ;;
  esac
}

robot_api_key_header() {
  local robot_host="${1:-${DEFAULT_ROBOT_HOST:-robot-a-01}}"
  printf 'X-Robot-Api-Key: %s' "$(robot_api_key "${robot_host}")"
}

client_tls_args() {
  if [ -n "${CLIENT_TLS_CERT_FILE:-}" ] && [ -n "${CLIENT_TLS_KEY_FILE:-}" ] \
    && [ -r "${CLIENT_TLS_CERT_FILE}" ] && [ -r "${CLIENT_TLS_KEY_FILE}" ]; then
    printf '%s\n' "--cert" "${CLIENT_TLS_CERT_FILE}" "--key" "${CLIENT_TLS_KEY_FILE}"
  fi
}

safe_get() {
  local url="$1"
  shift
  log_line "GET ${url}"
  curl -s "$@" $(client_tls_args) "${url}"
}

safe_post_json() {
  local url="$1"
  local body="$2"
  shift 2
  log_line "POST ${url} body=${body}"
  curl -s -X POST -H "Content-Type: application/json" "$@" $(client_tls_args) -d "${body}" "${url}"
}
