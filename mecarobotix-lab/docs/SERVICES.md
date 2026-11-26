# Service and Port Reference in Vulnerable Maquette

| Zone | Host | IP | Technology/Image | Services | Internal Ports | Published Host Ports |
|---|---|---:|---|---|---:|---:|
| Updates/DMZ | `diagnostic-server` | `10.10.2.10` | C diagnostic API behind socat TLS | Diagnostic API, robot updates, telemetry | `443` | `8443` |
| Internal | `ldap-server` | `10.10.1.10` | Bitnami OpenLDAP with LDAPS proxy | LDAP directory | `1389`, `1636` | none |
| Internal | `phpldapadmin` | `10.10.1.11` | phpLDAPadmin | LDAP admin UI | `80` | `8088` |
| Internal | `dns-server` | `10.10.1.12` | BIND9 | Internal DNS | `53/tcp`, `53/udp` | none |
| Internal | `devops-server` | `10.10.1.20` | Gitea with TLS | Git repositories | `3000`, `22` | `3000`, `2222` |
| Internal | `artifact-registry` | `10.10.1.23` | Nginx with TLS | Static firmware artifacts | `443` | none |
| Internal | `ci-server` | `10.10.1.21` | Jenkins behind socat TLS | CI/CD | `8443` | `8444` |
| Internal | `it-services` | `10.10.1.30` | Python/FastAPI placeholder | File-share/admin-panel | `80` | `8083` |
| Internal | `db-internal` | `10.10.1.31` | PostgreSQL 16 with TLS | Internal DB | `5432` | none |
| Internal | `backup-log-server` | `10.10.1.33` | Python/FastAPI placeholder | Backup/log placeholder | `80`, `514` | none |
| Internal | `ot-supervision` | `10.10.1.40` | Python/FastAPI placeholder | OT supervision API | `80` | `8090` |
| Internal | `ot-maintenance` | `10.10.1.41` | Debian + OpenSSH | Maintenance scripts / SSH | `22` | none |
| Internal | `robot-a-01` | `10.10.1.50` | Python/FastAPI robot API | Robot API | `8080` | none |
| Internal | `robot-a-02` | `10.10.1.51` | Python/FastAPI robot API | Robot API | `8080` | none |
| Internal | `robot-b-01` | `10.10.1.52` | Python/FastAPI robot API | Robot API | `8080` | none |
| Internal | `hacking-intranet-server` | `10.10.1.100` | Debian tools | Internal test workstation | none | none |
| Client | `client-robot-01` | `10.10.3.10` | Python/FastAPI robot API | External robot simulation | `8080` | none |
| Client | `client-robot-02` | `10.10.3.11` | Python/FastAPI robot API | External robot simulation | `8080` | none |
