#!/usr/bin/env bash

set -euo pipefail

# If docker-compose provides a command, run it directly.
# This is needed for ldap-ldaps-proxy, which uses this image only to run socat.
if [[ "$#" -gt 0 ]]; then
    exec "$@"
fi


required_variables=(
    LDAP_URI
    LDAP_BASE_DN
    LDAP_BIND_DN
    LDAP_ALLOWED_GROUPS
    LDAP_BIND_PASSWORD
)

for variable in "${required_variables[@]}"; do
    if [[ -z "${!variable:-}" ]]; then
        echo "Missing required environment variable: ${variable}" >&2
        exit 1
    fi
done

envsubst \
    '${LDAP_URI} ${LDAP_BASE_DN} ${LDAP_BIND_DN} ${LDAP_BIND_PASSWORD} ${LDAP_ALLOWED_GROUPS}' \
    < /etc/sssd/sssd.conf.template \
    > /etc/sssd/sssd.conf

unset LDAP_BIND_PASSWORD

chown root:root /etc/sssd/sssd.conf
chmod 0600 /etc/sssd/sssd.conf

rm -f /run/sssd.pid
mkdir -p /run/sshd /run/sssd /var/lib/sss/db /var/lib/sss/mc

echo "Starting SSSD..."
/usr/sbin/sssd --logger=files

echo "Starting SSH..."
exec /usr/sbin/sshd -D -e
