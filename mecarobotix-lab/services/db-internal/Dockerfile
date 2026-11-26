FROM postgres:16

RUN apt-get update && \
    apt-get install -y --no-install-recommends iproute2 && \
    rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /usr/local/bin/mecarobotix-postgres-entrypoint.sh

ENTRYPOINT ["/configure-network.sh", "/usr/local/bin/mecarobotix-postgres-entrypoint.sh"]
CMD ["postgres"]
