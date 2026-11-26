#!/bin/sh
set -eu

TLS_PORT="${TLS_PORT:-443}"
TLS_CERT_FILE="${TLS_CERT_FILE:-/etc/mecarobotix/tls/tls-chain.crt}"
TLS_KEY_FILE="${TLS_KEY_FILE:-/etc/mecarobotix/tls/tls.key}"
MTLS_CA_FILE="${MTLS_CA_FILE:-/etc/mecarobotix/pki/ca/ca.crt}"
ENABLE_MTLS="${ENABLE_MTLS:-true}"
NGINX_CONF="${NGINX_CONF:-/tmp/diagnostic-nginx.conf}"

start_binary_loop() {
    while true; do
        echo "[diagnostic-entrypoint] starting vulnerable binary on 127.0.0.1:${BINARY_PORT}" >&2
        set +e
        PORT="${BINARY_PORT}" /app/app
        status=$?
        set -e
        echo "[diagnostic-entrypoint] binary exited with status ${status}; restarting in ${RESTART_DELAY}s" >&2
        sleep "${RESTART_DELAY}"
    done
}

start_binary_loop &
binary_loop_pid=$!

term_handler() {
    kill "${binary_loop_pid}" 2>/dev/null || true
    wait "${binary_loop_pid}" 2>/dev/null || true
    exit 0
}

trap term_handler INT TERM

if [ ! -r "${TLS_CERT_FILE}" ] || [ ! -r "${TLS_KEY_FILE}" ]; then
    echo "[diagnostic-entrypoint] missing TLS files: ${TLS_CERT_FILE} / ${TLS_KEY_FILE}" >&2
    exit 1
fi

if [ "${ENABLE_MTLS}" = "true" ] && [ ! -r "${MTLS_CA_FILE}" ]; then
    echo "[diagnostic-entrypoint] missing mTLS CA file: ${MTLS_CA_FILE}" >&2
    exit 1
fi

if [ "${ENABLE_MTLS}" = "true" ]; then
    SSL_VERIFY_CLIENT="on"
    echo "[diagnostic-entrypoint] exposing HTTPS+mTLS with nginx on 0.0.0.0:${TLS_PORT}" >&2
else
    SSL_VERIFY_CLIENT="off"
    echo "[diagnostic-entrypoint] exposing HTTPS with nginx on 0.0.0.0:${TLS_PORT}" >&2
fi

cat > "${NGINX_CONF}" <<EOF
events {}

http {
    access_log /dev/stdout;
    error_log /dev/stderr info;

    server {
        listen ${TLS_PORT} ssl;
        server_name _;

        ssl_certificate ${TLS_CERT_FILE};
        ssl_certificate_key ${TLS_KEY_FILE};
        ssl_client_certificate ${MTLS_CA_FILE};
        ssl_verify_client ${SSL_VERIFY_CLIENT};
        ssl_verify_depth 2;
        ssl_protocols TLSv1.2 TLSv1.3;

        location / {
            proxy_pass http://127.0.0.1:${BINARY_PORT};
            proxy_http_version 1.1;
            proxy_set_header Host \$host;
            proxy_set_header X-Forwarded-Proto https;
            proxy_set_header X-MTLS-Verify \$ssl_client_verify;
            proxy_set_header X-MTLS-Subject-DN \$ssl_client_s_dn;
            proxy_set_header X-MTLS-Issuer-DN \$ssl_client_i_dn;
            proxy_set_header X-MTLS-Serial \$ssl_client_serial;
            proxy_set_header X-MTLS-Fingerprint \$ssl_client_fingerprint;
        }
    }
}
EOF

exec nginx -c "${NGINX_CONF}" -g "daemon off;"
