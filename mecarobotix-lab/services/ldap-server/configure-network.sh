#!/bin/sh
set -e

# Default gateway to reach internal networks
ip route replace 10.10.0.0/16 via 10.10.20.1

exec gosu 1001 "$@"
