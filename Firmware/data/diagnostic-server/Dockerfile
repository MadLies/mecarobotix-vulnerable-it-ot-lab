FROM ubuntu:24.04

RUN apt-get update \
    && apt-get install -y --no-install-recommends nginx curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY app /app/app
COPY docker-entrypoint.sh /usr/local/bin/diagnostic-entrypoint

RUN chmod +x /app/app /usr/local/bin/diagnostic-entrypoint

ENV TLS_PORT=443
ENV BINARY_PORT=8080
ENV RESTART_DELAY=0.2
ENV TLS_CERT_FILE=/etc/mecarobotix/tls/tls-chain.crt
ENV TLS_KEY_FILE=/etc/mecarobotix/tls/tls.key
ENV MTLS_CA_FILE=/etc/mecarobotix/pki/ca/ca.crt
ENV ENABLE_MTLS=true

EXPOSE 443

ENTRYPOINT ["diagnostic-entrypoint"]
