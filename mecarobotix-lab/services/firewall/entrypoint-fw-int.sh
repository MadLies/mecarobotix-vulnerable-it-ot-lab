#!/bin/sh
set -e

# --- Networking routing configuration
ip route replace 10.10.3.0/24 via 10.10.10.2


# --- Configuring firewall rules (ip-tables)
iptables -F

## Default policies
iptables -P INPUT   DROP
iptables -P OUTPUT  DROP
iptables -P FORWARD DROP

## Allows return traffic
iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT   -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT  -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

## INTERNAL: dns and ldap <- all
iptables -A FORWARD -s 10.10.0.0/16 -d 10.10.20.2   -j ACCEPT # To dns-server
iptables -A FORWARD -d 10.10.20.2   -s 10.10.0.0/16 -j ACCEPT # From dns-server
iptables -A FORWARD -s 10.10.0.0/16 -d 10.10.20.3   -j ACCEPT # To ldap-server

## INTERNAL: phpldapadmin <- IT
iptables -A FORWARD -s 10.10.40.0/24 -d 10.10.20.4 -j ACCEPT

## INTERNAL: backup-log-server -> DEV, OT
iptables -A FORWARD -s 10.10.40.4    -d 10.10.30.0/24 -j ACCEPT # DEV
iptables -A FORWARD -s 10.10.40.4    -d 10.10.50.0/24 -j ACCEPT # OT

## INTERNAL: it-services <- all
iptables -A FORWARD -s 10.10.0.0/16 -d 10.10.40.2 -j ACCEPT

## INTERNAL: ci-server <- robots
iptables -A FORWARD -s 10.10.50.101 -d 10.10.30.4 -j ACCEPT # robot-a-01
iptables -A FORWARD -s 10.10.50.102 -d 10.10.30.4 -j ACCEPT # robot-a-02
iptables -A FORWARD -s 10.10.50.103 -d 10.10.30.4 -j ACCEPT # robot-b-01

## DMZ <-> internal zones
iptables -A FORWARD -s 10.10.10.3 -d 10.10.30.3   -j ACCEPT # artifact-registry
iptables -A FORWARD -s 10.10.10.3 -d 10.10.40.3   -j ACCEPT # db-internal
iptables -A FORWARD -s 10.10.50.101 -d 10.10.10.3 -j ACCEPT # robot-a-01
iptables -A FORWARD -s 10.10.50.101 -d 10.10.10.3 -j ACCEPT # robot-a-02
iptables -A FORWARD -s 10.10.50.101 -d 10.10.10.3 -j ACCEPT # robot-b-01

## Allow ssh IT <-> router
iptables -A INPUT -s 10.10.40.0/24 -p tcp --dport 22 -j ACCEPT

## Loopback
iptables -A INPUT  -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

## Answers ping packets
iptables -A INPUT -s 10.10.0.0/16 -p icmp --icmp-type echo-request -j ACCEPT


# ---- Wireshark sniffing
#tcpdump -i any -nn -U -w - > /tcpdump &

exec "$@"
