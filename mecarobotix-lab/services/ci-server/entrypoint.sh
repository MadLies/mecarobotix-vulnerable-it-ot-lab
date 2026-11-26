#!/bin/bash
set -euo pipefail

JENKINS_HTTP_PORT="${JENKINS_HTTP_PORT:-8080}"
JENKINS_HTTPS_PORT="${JENKINS_HTTPS_PORT:-8443}"
TLS_CERT_FILE="${TLS_CERT_FILE:-/etc/mecarobotix/tls/tls-chain.crt}"
TLS_KEY_FILE="${TLS_KEY_FILE:-/etc/mecarobotix/tls/tls.key}"

if [ ! -r "${TLS_CERT_FILE}" ] || [ ! -r "${TLS_KEY_FILE}" ]; then
  echo "[ci-entrypoint] missing TLS files: ${TLS_CERT_FILE} / ${TLS_KEY_FILE}" >&2
  exit 1
fi

echo "[ci-entrypoint] starting Jenkins HTTP on 127.0.0.1:${JENKINS_HTTP_PORT}" >&2
/usr/local/bin/jenkins.sh --httpListenAddress=127.0.0.1 --httpPort="${JENKINS_HTTP_PORT}" &
jenkins_pid=$!

echo "[ci-entrypoint] exposing Jenkins HTTPS on 0.0.0.0:${JENKINS_HTTPS_PORT}" >&2
socat -d -d \
  "OPENSSL-LISTEN:${JENKINS_HTTPS_PORT},fork,reuseaddr,cert=${TLS_CERT_FILE},key=${TLS_KEY_FILE},verify=0" \
  "TCP:127.0.0.1:${JENKINS_HTTP_PORT}" &
socat_pid=$!

term_handler() {
  kill "${socat_pid}" "${jenkins_pid}" 2>/dev/null || true
  wait "${socat_pid}" 2>/dev/null || true
  wait "${jenkins_pid}" 2>/dev/null || true
}

trap 'term_handler; exit 0' INT TERM

set +e
wait -n "${jenkins_pid}" "${socat_pid}"
status=$?
set -e

term_handler
exit "${status}"
