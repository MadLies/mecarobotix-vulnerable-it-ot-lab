#!/bin/sh
set -e

/usr/sbin/sshd

exec uvicorn app:app --host 0.0.0.0 --port 80
