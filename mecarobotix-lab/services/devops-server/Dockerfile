FROM gitea/gitea:1.22

USER root

RUN apk add --no-cache sudo bash ca-certificates iproute2 \
    && adduser -D -s /bin/bash SuperTech \
    && echo 'SuperTech:SuperPassword' | chpasswd \
    && echo 'SuperTech ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/supertech \
    && chmod 0440 /etc/sudoers.d/supertech \
    && mkdir -p /run/sshd \
    && mkdir -p /etc/ssh \
    && touch /etc/ssh/sshd_config \
    && printf '\nPasswordAuthentication yes\nKbdInteractiveAuthentication yes\nAllowUsers git SuperTech\n' >> /etc/ssh/sshd_config
