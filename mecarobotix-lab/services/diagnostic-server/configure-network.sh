#!/bin/sh
set -e

ip route replace 10.10.3.0/24 via 10.10.10.2 # client-robots
ip route replace 10.10.0.0/16 via 10.10.10.1 # internal networks

exec "$@"