#!/bin/sh
set -eu

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

echo "[diagnostic-entrypoint] exposing service with socat on 0.0.0.0:${SOCAT_PORT}" >&2
exec socat -d -d "TCP-LISTEN:${SOCAT_PORT},fork,reuseaddr" "TCP:127.0.0.1:${BINARY_PORT}"
