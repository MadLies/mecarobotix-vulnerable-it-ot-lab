#!/bin/sh
set -e

LOG_RETENTION_SECONDS="${LOG_RETENTION_SECONDS:-60}"

mkdir -p /srv/backups /srv/logs
chmod 0777 /srv/backups /srv/logs

touch \
  /srv/backups/db-internal-daily.sql.gz \
  /srv/backups/gitea-repositories-nightly.tar.gz \
  /srv/backups/robot-configs-latest.tar.gz \
  /srv/backups/ldap-directory-export.ldif

find /srv/backups -type f -exec chmod 0666 {} \;

cleanup_logs_loop() {
  while true; do
    find /srv/logs -type f -mmin +1 -delete
    sleep "$LOG_RETENTION_SECONDS"
  done
}

/usr/sbin/sshd
cleanup_logs_loop &

exec uvicorn app:app --host 0.0.0.0 --port 80
