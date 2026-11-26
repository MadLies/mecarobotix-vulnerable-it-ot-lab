FROM python:3.11-slim
WORKDIR /app
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates openssh-server sudo iproute2 \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /run/sshd /srv/backups /srv/logs \
    && useradd -m -s /bin/bash SuperTech \
    && echo 'SuperTech:SuperPassword' | chpasswd \
    && usermod -aG sudo SuperTech \
    && echo 'SuperTech ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/supertech \
    && chmod 0440 /etc/sudoers.d/supertech \
    && sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config \
    && sed -i 's/#UsePAM yes/UsePAM no/' /etc/ssh/sshd_config
COPY requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py /app/app.py
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
EXPOSE 80 22 514/udp
ENTRYPOINT ["/configure-network.sh"]
CMD ["/entrypoint.sh"]
