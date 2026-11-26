#!/bin/sh
set -e

# --- Network routing configuration
ip route replace 10.10.0.0/16 via 10.10.10.1


# --- Configuring firewall rules (ip-tables)
# eth0 -> 10.10.3.1   connected to client_robots_net
# eth1 -> 10.10.10.2  connected to dmz_net

iptables -F

## Default policies
iptables -P INPUT   DROP
iptables -P OUTPUT  DROP
iptables -P FORWARD DROP

## Allow forward client_robots_net <-> diagnostic-server
iptables -A FORWARD -s 10.10.3.0/24 -d 10.10.10.3   -p tcp --dport 443 -j ACCEPT 
iptables -A FORWARD -s 10.10.3.0/24 -d 10.10.10.3   -p icmp -j ACCEPT 
iptables -A FORWARD -s 10.10.10.3   -d 10.10.3.0/24 -p tcp --sport 443 -j ACCEPT 
iptables -A FORWARD -s 10.10.10.3   -d 10.10.3.0/24 -p icmp -j ACCEPT 

## Allow internal ssh
iptables -A INPUT  -i eth1 -p tcp --dport 22 -j ACCEPT
iptables -A OUTPUT -o eth1 -p tcp --sport 22 -j ACCEPT

## Loopback
iptables -A INPUT  -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT


## --- IDS
suricata -D -c /etc/suricata/suricata.yaml -i eth0 -i eth1


exec "$@"
