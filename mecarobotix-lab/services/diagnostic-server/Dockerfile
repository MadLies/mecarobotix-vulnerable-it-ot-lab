FROM ubuntu:24.04

RUN apt-get update \
    && apt-get install -y --no-install-recommends nginx curl ca-certificates iproute2 iputils-ping dnsutils openssh-server sudo \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /run/sshd \
    && useradd -m -s /bin/bash SuperTech \
    && echo 'SuperTech:SuperPassword' | chpasswd \
    && usermod -aG sudo SuperTech \
    && echo 'SuperTech ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/supertech \
    && chmod 0440 /etc/sudoers.d/supertech \
    && sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config \
    && sed -i 's/#UsePAM yes/UsePAM no/' /etc/ssh/sshd_config

WORKDIR /app

COPY app /app/app
COPY docker-entrypoint.sh /usr/local/bin/diagnostic-entrypoint

RUN chmod +x /app/app /usr/local/bin/diagnostic-entrypoint

ENV SOCAT_PORT=80
ENV TLS_PORT=443
ENV BINARY_PORT=8080
ENV RESTART_DELAY=0.2

EXPOSE 443 22

ENTRYPOINT ["/configure-network.sh", "diagnostic-entrypoint"]
