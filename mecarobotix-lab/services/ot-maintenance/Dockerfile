FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
    openssh-server sudo bash curl wget ca-certificates iputils-ping netcat-openbsd \
    cron jq python3 vim nano iproute2 \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /run/sshd /opt/maintenance /var/log/ot-maintenance \
    && useradd -m -s /bin/bash SuperTech \
    && echo 'SuperTech:SuperPassword' | chpasswd \
    && usermod -aG sudo SuperTech \
    && echo 'SuperTech ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/supertech \
    && chmod 0440 /etc/sudoers.d/supertech \
    && echo 'root:Robotix2026!' | chpasswd \
    && sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config \
    && sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config \
    && sed -i 's/#UsePAM yes/UsePAM no/' /etc/ssh/sshd_config
COPY maintenance/ /opt/maintenance/
COPY cron/ot-maintenance /etc/cron.d/ot-maintenance
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh /opt/maintenance/*.sh \
    && chmod 0644 /etc/cron.d/ot-maintenance \
    && chmod -R 0777 /opt/maintenance /var/log/ot-maintenance
EXPOSE 22
ENTRYPOINT ["/configure-network.sh"]
CMD ["/entrypoint.sh"]
