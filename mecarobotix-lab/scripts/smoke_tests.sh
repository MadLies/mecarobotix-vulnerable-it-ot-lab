#!/bin/bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "$PROJECT_ROOT"

if [ -f .env ]; then
  set -a
  # shellcheck disable=SC1091
  . ./.env
  set +a
fi

CA_CERT="${CA_CERT:-data/pki/ca/ca.crt}"
CI_CLIENT_CERT="${CI_CLIENT_CERT:-data/pki/clients/ci-server/client-chain.crt}"
CI_CLIENT_KEY="${CI_CLIENT_KEY:-data/pki/clients/ci-server/client.key}"

CONTAINER_CA_CERT="${CONTAINER_CA_CERT:-/etc/mecarobotix/pki/ca/ca.crt}"
CONTAINER_CLIENT_CERT="${CONTAINER_CLIENT_CERT:-/etc/mecarobotix/client-tls/client-chain.crt}"
CONTAINER_CLIENT_KEY="${CONTAINER_CLIENT_KEY:-/etc/mecarobotix/client-tls/client.key}"

DIAGNOSTIC_HTTPS_HOST_PORT="${DIAGNOSTIC_HTTPS_HOST_PORT:-8443}"
DIAGNOSTIC_HTTP_HOST_PORT="${DIAGNOSTIC_HTTP_HOST_PORT:-${DIAGNOSTIC_HOST_PORT:-8080}}"
DIAGNOSTIC_HTTPS_URL="${DIAGNOSTIC_HTTPS_URL:-https://localhost:${DIAGNOSTIC_HTTPS_HOST_PORT}}"
DIAGNOSTIC_HTTP_URL="${DIAGNOSTIC_HTTP_URL:-http://localhost:${DIAGNOSTIC_HTTP_HOST_PORT}}"
DIAGNOSTIC_INTERNAL_URL="${DIAGNOSTIC_INTERNAL_URL:-https://diagnostic-server.mecarobotix.local}"

ROBOT_HOST="${ROBOT_HOST:-robot-a-01}"
ROBOT_TYPE="${ROBOT_TYPE:-A}"
ROBOT_STATUS_URL="${ROBOT_STATUS_URL:-https://${ROBOT_HOST}:8443/status}"

ARTIFACT_FIRMWARE_URL="${ARTIFACT_FIRMWARE_URL:-https://artifact-registry/firmware/robot-a-latest.bin}"
ARTIFACT_FIRMWARE_HTTP_URL="${ARTIFACT_FIRMWARE_HTTP_URL:-http://artifact-registry/firmware/robot-a-latest.bin}"

JENKINS_USER="${JENKINS_USER:-${JENKINS_ADMIN_USER:-jenkins_admin}}"
JENKINS_PASSWORD="${JENKINS_PASSWORD:-${JENKINS_ADMIN_PASSWORD:-Admin123!}}"
JENKINS_HTTPS_HOST_PORT="${JENKINS_HTTPS_HOST_PORT:-8444}"
JENKINS_JOB="${JENKINS_JOB:-sync-gitea-release-to-artifact-registry}"
JENKINS_HOST_URL="${JENKINS_HOST_URL:-https://localhost:${JENKINS_HTTPS_HOST_PORT}}"
JENKINS_HTTP_URL="${JENKINS_HTTP_URL:-http://localhost:${JENKINS_HTTPS_HOST_PORT}}"
JENKINS_INTERNAL_URL="${JENKINS_INTERNAL_URL:-https://ci-server:8443}"

LDAP_ADMIN_DN="${LDAP_ADMIN_DN:-cn=admin,dc=mecarobotix,dc=local}"
LDAP_ADMIN_PASSWORD="${LDAP_ADMIN_PASSWORD:-Admin123!}"
LDAPS_URL="${LDAPS_URL:-ldaps://ldap-server:1636}"

GITEA_HOST_PORT="${GITEA_HOST_PORT:-3000}"
GITEA_HTTPS_URL="${GITEA_HTTPS_URL:-https://localhost:${GITEA_HOST_PORT}}"
GITEA_HTTP_URL="${GITEA_HTTP_URL:-http://localhost:${GITEA_HOST_PORT}}"

POSTGRES_DB="${POSTGRES_DB:-mecarobotix}"
POSTGRES_USER="${POSTGRES_USER:-admin_db}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-Admin123!}"
POSTGRES_HOST="${POSTGRES_HOST:-db-internal}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
COMPOSE_CMD="${COMPOSE_CMD:-docker compose}"

PASS_COUNT=0
FAIL_COUNT=0

if [ -n "${NO_COLOR:-}" ]; then
  BOLD=""
  DIM=""
  RED=""
  GREEN=""
  YELLOW=""
  BLUE=""
  CYAN=""
  RESET=""
else
  BOLD=$'\033[1m'
  DIM=$'\033[2m'
  RED=$'\033[31m'
  GREEN=$'\033[32m'
  YELLOW=$'\033[33m'
  BLUE=$'\033[34m'
  CYAN=$'\033[36m'
  RESET=$'\033[0m'
fi

compose() {
  # COMPOSE_CMD is intentionally split so callers can set:
  # COMPOSE_CMD="sudo docker compose" ./scripts/smoke_tests.sh
  # shellcheck disable=SC2086
  $COMPOSE_CMD "$@"
}

print_step() {
  printf "\n%s%s[+]%s %s%s%s\n" "$BOLD" "$BLUE" "$RESET" "$BOLD" "$1" "$RESET"
}

expect_success() {
  local name="$1"
  shift

  print_step "$name"
  if "$@"; then
    printf "%s[PASS]%s %s\n" "$GREEN" "$RESET" "$name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    printf "%s[FAIL]%s %s\n" "$RED" "$RESET" "$name" >&2
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

expect_failure() {
  local name="$1"
  shift

  print_step "$name"
  if "$@"; then
    printf "%s[FAIL]%s %s unexpectedly succeeded\n" "$RED" "$RESET" "$name" >&2
    FAIL_COUNT=$((FAIL_COUNT + 1))
  else
    printf "%s[PASS]%s %s%s failed as expected%s\n" "$GREEN" "$RESET" "$name" "$DIM" "$RESET"
    PASS_COUNT=$((PASS_COUNT + 1))
  fi
}

jenkins_job_api_path="/job/${JENKINS_JOB}/api/json"

if ! compose ps >/dev/null 2>&1; then
  printf "%s[FAIL]%s Docker Compose is not accessible with COMPOSE_CMD='%s'\n" "$RED" "$RESET" "$COMPOSE_CMD" >&2
  printf "       Start the lab first or run with: %sCOMPOSE_CMD='sudo docker compose' %s%s\n" "$YELLOW" "$0" "$RESET" >&2
  exit 2
fi

expect_success "diagnostic-server HTTPS health with mTLS from host" \
  curl --cacert "$CA_CERT" \
    --cert "$CI_CLIENT_CERT" \
    --key "$CI_CLIENT_KEY" \
    -fsS "${DIAGNOSTIC_HTTPS_URL}/health"

expect_failure "diagnostic-server legacy HTTP endpoint is not accessible" \
  curl -fsS "${DIAGNOSTIC_HTTP_URL}/health"

expect_failure "diagnostic-server rejects plain HTTP on HTTPS port" \
  curl -fsS "http://localhost:${DIAGNOSTIC_HTTPS_HOST_PORT}/health"

expect_success "robot status over HTTPS+mTLS from ot-maintenance" \
  compose exec -T ot-maintenance curl --cacert "$CONTAINER_CA_CERT" \
    --cert "$CONTAINER_CLIENT_CERT" \
    --key "$CONTAINER_CLIENT_KEY" \
    -fsS "$ROBOT_STATUS_URL"

expect_failure "robot status without client certificate is rejected" \
  compose exec -T ot-maintenance curl --cacert "$CONTAINER_CA_CERT" \
    -fsS "$ROBOT_STATUS_URL"

expect_success "artifact-registry firmware download over HTTPS from ci-server" \
  compose exec -T ci-server curl --cacert "$CONTAINER_CA_CERT" \
    -fsS "$ARTIFACT_FIRMWARE_URL" \
    -o /tmp/robot-a-latest.bin

expect_failure "artifact-registry plain HTTP firmware download is not accessible" \
  compose exec -T ci-server curl -fsS "$ARTIFACT_FIRMWARE_HTTP_URL" \
    -o /tmp/robot-a-latest-http.bin

expect_success "Jenkins HTTPS job API from host" \
  curl --cacert "$CA_CERT" \
    -u "${JENKINS_USER}:${JENKINS_PASSWORD}" \
    -fsS "${JENKINS_HOST_URL}${jenkins_job_api_path}"

expect_failure "Jenkins rejects plain HTTP on HTTPS port" \
  curl -fsS "${JENKINS_HTTP_URL}${jenkins_job_api_path}"

expect_success "Jenkins HTTPS job API from artifact-registry container" \
  compose exec -T artifact-registry curl --cacert "$CONTAINER_CA_CERT" \
    -u "${JENKINS_USER}:${JENKINS_PASSWORD}" \
    -fsS "${JENKINS_INTERNAL_URL}${jenkins_job_api_path}"

expect_success "LDAPS bind from ldap-server" \
  compose exec -T ldap-server env \
    LDAP_ADMIN_DN="$LDAP_ADMIN_DN" \
    LDAP_ADMIN_PASSWORD="$LDAP_ADMIN_PASSWORD" \
    LDAPS_URL="$LDAPS_URL" \
    bash -lc 'LDAPTLS_CACERT=/etc/mecarobotix/pki/ca/ca.crt ldapwhoami -x -H "$LDAPS_URL" -D "$LDAP_ADMIN_DN" -w "$LDAP_ADMIN_PASSWORD"'

expect_success "Gitea HTTPS health from host" \
  curl --cacert "$CA_CERT" \
    -fsS "${GITEA_HTTPS_URL}/api/healthz"

expect_failure "Gitea rejects plain HTTP on HTTPS port" \
  curl -fsS "${GITEA_HTTP_URL}/api/healthz"

expect_success "PostgreSQL TLS verify-full connection" \
  compose exec -T db-internal env \
    PGPASSWORD="$POSTGRES_PASSWORD" \
    POSTGRES_DB="$POSTGRES_DB" \
    POSTGRES_USER="$POSTGRES_USER" \
    POSTGRES_HOST="$POSTGRES_HOST" \
    POSTGRES_PORT="$POSTGRES_PORT" \
    bash -lc 'psql "host=$POSTGRES_HOST port=$POSTGRES_PORT dbname=$POSTGRES_DB user=$POSTGRES_USER sslmode=verify-full sslrootcert=/etc/mecarobotix/pki/ca/ca.crt" -c "select ssl from pg_stat_ssl where pid = pg_backend_pid();"'

expect_failure "PostgreSQL non-TLS connection is rejected" \
  compose exec -T db-internal env \
    PGPASSWORD="$POSTGRES_PASSWORD" \
    POSTGRES_DB="$POSTGRES_DB" \
    POSTGRES_USER="$POSTGRES_USER" \
    POSTGRES_HOST="$POSTGRES_HOST" \
    POSTGRES_PORT="$POSTGRES_PORT" \
    bash -lc 'psql "host=$POSTGRES_HOST port=$POSTGRES_PORT dbname=$POSTGRES_DB user=$POSTGRES_USER sslmode=disable" -c "select 1;"'

expect_success "robot-a-01 can call diagnostic-server firmware API over HTTPS+mTLS" \
  compose exec -T robot-a-01 bash -lc \
    'curl --cacert /etc/mecarobotix/pki/ca/ca.crt -fsS --cert "$CLIENT_TLS_CERT_FILE" --key "$CLIENT_TLS_KEY_FILE" "https://diagnostic-server.mecarobotix.local/api/firmware/latest?robot_type=A"'

expect_success "diagnostic-server firmware API over HTTPS+mTLS from host" \
  curl --cacert "$CA_CERT" \
    --cert "$CI_CLIENT_CERT" \
    --key "$CI_CLIENT_KEY" \
    -fsS "${DIAGNOSTIC_HTTPS_URL}/api/firmware/latest?robot_type=${ROBOT_TYPE}"

expect_failure "diagnostic-server firmware API rejects request without client certificate" \
  curl --cacert "$CA_CERT" \
    -fsS "${DIAGNOSTIC_HTTPS_URL}/api/firmware/latest?robot_type=${ROBOT_TYPE}"

if [ "$FAIL_COUNT" -eq 0 ]; then
  printf "\n%s%s[+] Smoke test summary:%s %s%s passed%s, %s%s failed%s\n" \
    "$BOLD" "$CYAN" "$RESET" "$GREEN" "$PASS_COUNT" "$RESET" "$GREEN" "$FAIL_COUNT" "$RESET"
else
  printf "\n%s%s[+] Smoke test summary:%s %s%s passed%s, %s%s failed%s\n" \
    "$BOLD" "$CYAN" "$RESET" "$GREEN" "$PASS_COUNT" "$RESET" "$RED" "$FAIL_COUNT" "$RESET"
fi

if [ "$FAIL_COUNT" -ne 0 ]; then
  exit 1
fi
