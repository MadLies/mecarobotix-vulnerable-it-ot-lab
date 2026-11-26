#!/bin/sh
set -e

FTP_USER="${FTP_USER:-ftpUser}"
FTP_PASSWORD="${FTP_PASSWORD:-ftpPassword}"
FTP_UID="${FTP_UID:-1000}"
SMB_USER="${SMB_USER:-smbByLdapUser}"
SMB_PASSWORD="${SMB_PASSWORD:-smbByLdapPassword}"
SMB_UID="${SMB_UID:-1090}"
SMB_GID="${SMB_GID:-1004}"
LDAP_URL="${LDAP_URI:-ldaps://ldap.mecarobotix.local:1636}"
LDAP_BASE_DN="${LDAP_BASE_DN:-dc=mecarobotix,dc=local}"
LDAP_ADMIN_DN="${LDAP_ADMIN_DN:-cn=admin,dc=mecarobotix,dc=local}"
LDAP_ADMIN_PASSWORD="${LDAP_ADMIN_PASSWORD:-Admin123!}"

mkdir -p /srv/share /var/run/vsftpd/empty /var/run/samba /var/log/samba /var/cache/samba /var/lib/samba

if ! id "$FTP_USER" >/dev/null 2>&1; then
  useradd --uid "$FTP_UID" --non-unique --home-dir /srv/share --shell /bin/bash "$FTP_USER"
fi

echo "$FTP_USER:$FTP_PASSWORD" | chpasswd

echo "[+] Waiting for LDAP at $LDAP_URL..."
until ldapsearch -x -H "$LDAP_URL" -D "$LDAP_ADMIN_DN" -w "$LDAP_ADMIN_PASSWORD" -b "" -s base dn >/tmp/ldap-wait.log 2>&1; do
  echo "[!] LDAP is not ready yet:"
  sed 's/^/    /' /tmp/ldap-wait.log
  sleep 2
done
echo "[+] LDAP is reachable."

if ! ldapsearch -x -H "$LDAP_URL" -D "$LDAP_ADMIN_DN" -w "$LDAP_ADMIN_PASSWORD" -b "$LDAP_BASE_DN" -s base dn >/dev/null 2>&1; then
  echo "[+] Creating missing LDAP base DN: $LDAP_BASE_DN"
  ldapadd -x -H "$LDAP_URL" -D "$LDAP_ADMIN_DN" -w "$LDAP_ADMIN_PASSWORD" <<LDIF || true
dn: $LDAP_BASE_DN
objectClass: top
objectClass: dcObject
objectClass: organization
o: MecaRobotix
dc: mecarobotix
LDIF
fi

for OU in people groups services robots; do
  if ! ldapsearch -x -H "$LDAP_URL" -D "$LDAP_ADMIN_DN" -w "$LDAP_ADMIN_PASSWORD" -b "ou=$OU,$LDAP_BASE_DN" -s base dn >/dev/null 2>&1; then
    echo "[+] Creating missing LDAP OU: ou=$OU,$LDAP_BASE_DN"
    ldapadd -x -H "$LDAP_URL" -D "$LDAP_ADMIN_DN" -w "$LDAP_ADMIN_PASSWORD" <<LDIF || true
dn: ou=$OU,$LDAP_BASE_DN
objectClass: organizationalUnit
ou: $OU
LDIF
  fi
done

SMB_USER_DN="uid=$SMB_USER,ou=people,$LDAP_BASE_DN"

if ldapsearch -x -H "$LDAP_URL" -D "$LDAP_ADMIN_DN" -w "$LDAP_ADMIN_PASSWORD" -b "$SMB_USER_DN" -s base dn >/dev/null 2>&1; then
  echo "[+] Updating shared SMB LDAP account: $SMB_USER"
  ldapmodify -x -H "$LDAP_URL" -D "$LDAP_ADMIN_DN" -w "$LDAP_ADMIN_PASSWORD" <<LDIF
dn: $SMB_USER_DN
changetype: modify
replace: userPassword
userPassword: $SMB_PASSWORD
LDIF
else
  echo "[+] Creating shared SMB LDAP account: $SMB_USER"
  ldapadd -x -H "$LDAP_URL" -D "$LDAP_ADMIN_DN" -w "$LDAP_ADMIN_PASSWORD" <<LDIF
dn: $SMB_USER_DN
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
cn: Shared SMB LDAP User
sn: SharedSMB
uid: $SMB_USER
uidNumber: $SMB_UID
gidNumber: $SMB_GID
homeDirectory: /srv/share
loginShell: /bin/bash
userPassword: $SMB_PASSWORD
description: Shared privileged LDAP account used by workers to access SMB file share
LDIF
fi

ldapwhoami -x -H "$LDAP_URL" -D "$SMB_USER_DN" -w "$SMB_PASSWORD" >/dev/null
echo "[+] LDAP credentials validated for SMB account: $SMB_USER"

for GROUP in it_admins administrative service_accounts; do
  if ! ldapsearch -x -H "$LDAP_URL" -D "$LDAP_ADMIN_DN" -w "$LDAP_ADMIN_PASSWORD" -b "cn=$GROUP,ou=groups,$LDAP_BASE_DN" -s base dn >/dev/null 2>&1; then
    echo "[+] Creating missing privileged LDAP group: $GROUP"
    ldapadd -x -H "$LDAP_URL" -D "$LDAP_ADMIN_DN" -w "$LDAP_ADMIN_PASSWORD" <<LDIF || true
dn: cn=$GROUP,ou=groups,$LDAP_BASE_DN
objectClass: groupOfNames
cn: $GROUP
member: $SMB_USER_DN
LDIF
  fi
done

for GROUP in it_admins administrative service_accounts; do
  ldapmodify -x -H "$LDAP_URL" -D "$LDAP_ADMIN_DN" -w "$LDAP_ADMIN_PASSWORD" <<LDIF || true
dn: cn=$GROUP,ou=groups,$LDAP_BASE_DN
changetype: modify
add: member
member: $SMB_USER_DN
LDIF
done

if ! id "$SMB_USER" >/dev/null 2>&1; then
  useradd --uid "$SMB_UID" --non-unique --home-dir /srv/share --shell /bin/bash "$SMB_USER"
fi

echo "$SMB_USER:$SMB_PASSWORD" | chpasswd
printf '%s\n%s\n' "$SMB_PASSWORD" "$SMB_PASSWORD" | smbpasswd -a -s "$SMB_USER" >/dev/null
smbpasswd -e "$SMB_USER" >/dev/null

cp /etc/vsftpd.conf /tmp/vsftpd.conf

if [ -n "${FTP_PASV_ADDRESS:-}" ]; then
  echo "pasv_address=$FTP_PASV_ADDRESS" >> /tmp/vsftpd.conf
fi

vsftpd /tmp/vsftpd.conf &
smbd --foreground --no-process-group --configfile=/etc/samba/smb.conf &
/usr/sbin/sshd

sleep 1
pgrep smbd >/dev/null

exec uvicorn app:app --host 0.0.0.0 --port 80
