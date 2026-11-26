#!/bin/sh
set -eu

ROBOT_HTTP_PORT="${ROBOT_HTTP_PORT:-8080}"
ROBOT_HTTPS_PORT="${ROBOT_HTTPS_PORT:-8443}"
ROBOT_APP_PORT="${ROBOT_APP_PORT:-18080}"
TLS_CERT_FILE="${TLS_CERT_FILE:-/etc/mecarobotix/tls/tls-chain.crt}"
TLS_KEY_FILE="${TLS_KEY_FILE:-/etc/mecarobotix/tls/tls.key}"
MTLS_CA_FILE="${MTLS_CA_FILE:-/etc/mecarobotix/pki/ca/ca.crt}"
ENABLE_MTLS="${ENABLE_MTLS:-true}"
ENABLE_LEGACY_HTTP="${ENABLE_LEGACY_HTTP:-true}"
NGINX_CONF="${NGINX_CONF:-/tmp/robot-api-nginx.conf}"

if [ ! -r "${TLS_CERT_FILE}" ] || [ ! -r "${TLS_KEY_FILE}" ]; then
    echo "[robot-api-entrypoint] missing TLS files: ${TLS_CERT_FILE} / ${TLS_KEY_FILE}" >&2
    exit 1
fi

if [ "${ENABLE_MTLS}" = "true" ] && [ ! -r "${MTLS_CA_FILE}" ]; then
    echo "[robot-api-entrypoint] missing mTLS CA file: ${MTLS_CA_FILE}" >&2
    exit 1
fi

echo "[robot-api-entrypoint] starting internal API on 127.0.0.1:${ROBOT_APP_PORT}" >&2
uvicorn app:app --host 127.0.0.1 --port "${ROBOT_APP_PORT}" &
app_pid=$!
legacy_http_pid=""

term_handler() {
    kill "${app_pid}" 2>/dev/null || true
    wait "${app_pid}" 2>/dev/null || true
    exit 0
}

trap term_handler INT TERM

if [ "${ENABLE_MTLS}" = "true" ]; then
    SSL_VERIFY_CLIENT="on"
    echo "[robot-api-entrypoint] starting HTTPS+mTLS API with nginx on 0.0.0.0:${ROBOT_HTTPS_PORT}" >&2
else
    SSL_VERIFY_CLIENT="off"
    echo "[robot-api-entrypoint] starting HTTPS API with nginx on 0.0.0.0:${ROBOT_HTTPS_PORT}" >&2
fi

cat > "${NGINX_CONF}" <<EOF
events {}

http {
    access_log /dev/stdout;
    error_log /dev/stderr info;

    server {
        listen ${ROBOT_HTTPS_PORT} ssl;
        server_name _;

        ssl_certificate ${TLS_CERT_FILE};
        ssl_certificate_key ${TLS_KEY_FILE};
        ssl_client_certificate ${MTLS_CA_FILE};
        ssl_verify_client ${SSL_VERIFY_CLIENT};
        ssl_verify_depth 2;
        ssl_protocols TLSv1.2 TLSv1.3;

        location / {
            proxy_pass http://127.0.0.1:${ROBOT_APP_PORT};
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
EOF

if [ "${ENABLE_LEGACY_HTTP}" = "true" ]; then
    cat >> "${NGINX_CONF}" <<EOF

    server {
        listen ${ROBOT_HTTP_PORT};
        server_name _;

        location / {
            proxy_pass http://127.0.0.1:${ROBOT_APP_PORT};
            proxy_http_version 1.1;
            proxy_set_header Host \$host;
            proxy_set_header X-Forwarded-Proto http;
            proxy_set_header X-MTLS-Verify NONE;
        }
    }
EOF
fi

cat >> "${NGINX_CONF}" <<EOF
}
EOF

exec nginx -c "${NGINX_CONF}" -g "daemon off;"
