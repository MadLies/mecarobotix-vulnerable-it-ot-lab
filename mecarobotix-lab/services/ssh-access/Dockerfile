FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates openssh-server sudo bash procps iproute2 iputils-ping dnsutils netcat-openbsd curl socat vim nano \
        ldap-utils gettext-base sssd-common sssd-ldap sssd-tools libnss-sss libpam-sss libpam-modules \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /run/sshd /run/sssd /var/lib/sss/db /var/lib/sss/mc \
    \
    # NSS: check local users first, then LDAP users through SSSD.
    && sed -ri 's/^passwd:.*/passwd:         files sss/' /etc/nsswitch.conf \
    && sed -ri 's/^group:.*/group:          files sss/' /etc/nsswitch.conf \
    && sed -ri 's/^shadow:.*/shadow:         files sss/' /etc/nsswitch.conf \
    \
    # Enable the PAM profile installed by libpam-sss.
    && pam-auth-update --enable sss --force \
    \
    # Automatically create /home/<username> on first login.
    && printf '%s\n' \
        'session required pam_mkhomedir.so skel=/etc/skel umask=0077' \
        >> /etc/pam.d/sshd \
    \
    # SSH must use PAM for LDAP authentication.
    && printf '%s\n' \
        'UsePAM yes' \
        'PasswordAuthentication yes' \
        'KbdInteractiveAuthentication no' \
        'PermitEmptyPasswords no' \
        'PermitRootLogin no' \
        > /etc/ssh/sshd_config.d/20-ldap-auth.conf

COPY sssd.conf.template /etc/sssd/sssd.conf.template
COPY entrypoint.sh /usr/local/sbin/entrypoint.sh

RUN chmod 0755 /usr/local/sbin/entrypoint.sh

EXPOSE 22

ENTRYPOINT ["/usr/local/sbin/entrypoint.sh"]
