FROM ubuntu:24.04

RUN apt-get update \
    && apt-get install -y --no-install-recommends socat curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY app /app/app
COPY docker-entrypoint.sh /usr/local/bin/diagnostic-entrypoint

RUN chmod +x /app/app /usr/local/bin/diagnostic-entrypoint

ENV SOCAT_PORT=80
ENV BINARY_PORT=8080
ENV RESTART_DELAY=0.2

EXPOSE 80

ENTRYPOINT ["diagnostic-entrypoint"]
