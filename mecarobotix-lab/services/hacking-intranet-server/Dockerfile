FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash curl wget ca-certificates iproute2 iputils-ping traceroute dnsutils \
    netcat-openbsd nmap ldap-utils postgresql-client openssh-client openssh-server sudo git \
    procps vim nano jq ftp \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /run/sshd \
    && useradd -m -s /bin/bash SuperTech \
    && echo 'SuperTech:SuperPassword' | chpasswd \
    && usermod -aG sudo SuperTech \
    && echo 'SuperTech ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/supertech \
    && chmod 0440 /etc/sudoers.d/supertech \
    && sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config \
    && sed -i 's/#UsePAM yes/UsePAM no/' /etc/ssh/sshd_config
WORKDIR /root
CMD ["/bin/bash"]
