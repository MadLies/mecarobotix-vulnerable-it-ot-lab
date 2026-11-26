# A DNS Zone Transfer is a way to synchronize two DNS servers
# in a network. If bad configured (as here, `allow-transfer` allows
# everyone to ask for a transfer in lab/configs/dns/named.conf),
# it can be used to map all hosts registered in the DNS.

DNS=$(dig +short ns mecarobotix.local)
dig axfr mecarobotix.local @${DNS}
