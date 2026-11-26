#!/bin/bash
set -e

mkdir -p /var/log/ot-maintenance /opt/maintenance/backups
touch /var/log/ot-maintenance/operations.log \
  /var/log/ot-maintenance/hourly-status.log \
  /var/log/ot-maintenance/hourly-updates.log \
  /var/log/ot-maintenance/hourly-backups.log \
  /var/log/ot-maintenance/hourly-firmware-requests.log

chmod -R 0777 /opt/maintenance /var/log/ot-maintenance

/usr/sbin/cron
exec /usr/sbin/sshd -D -e
