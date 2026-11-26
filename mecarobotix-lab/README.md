# MécaRobotix Docker Compose Lab

**DOCUMENT NOT UP TO DATE WITH FIXED PROPOSAL**

This repository contains the first deployable Docker Compose structure for the MécaRobotix base infrastructure lab.

The goal of this version is to make the infrastructure run and allow the team to connect to the services. It intentionally reflects a weak initial design, but the first objective is functionality, not exploitation.

## Important design notes

- No `mgmt_net` is used for now.
- There is no `internal_flat_net -> client_robot_net` communication rule.
- `diagnostic-server` is exposed on the Docker host to simulate a public diagnostic endpoint.
- The current `diagnostic-server` is a Python/FastAPI placeholder. Later it can be replaced by the custom vulnerable binary service used by the lab.
- The `diagnostic-server` is connected to both `updates_net` and `internal_flat_net` to simulate the excessive DMZ-to-internal access rule in a simple way.

## Networks

| Network | CIDR | Purpose |
|---|---:|---|
| `updates_net` | `10.10.2.0/24` | DMZ / Updates Network |
| `internal_flat_net` | `10.10.1.0/24` | Internal flat network with IT, DEV, OT, users and infrastructure services |
| `client_robot_net` | `10.10.3.0/24` | External/client robot simulation |

## Main hosts

| Host | IP | Services |
|---|---:|---|
| `diagnostic-server` | `10.10.2.10` and `10.10.1.110` | Public diagnostic API, robot updates, telemetry intake |
| `ldap-server` | `10.10.1.10` | OpenLDAP |
| `phpldapadmin` | `10.10.1.11` | LDAP web administration |
| `dns-server` | `10.10.1.12` | Internal DNS |
| `devops-server` | `10.10.1.20` | Gitea |
| `ci-server` | `10.10.1.21` | Jenkins CI/CD |
| `artifact-registry` | `10.10.1.23` | Static firmware artifact server |
| `it-services` | `10.10.1.30` | File-share and internal admin panel placeholder |
| `db-internal` | `10.10.1.31` | PostgreSQL database with TLS |
| `backup-log-server` | `10.10.1.33` | Backup/log placeholder |
| `ot-supervision` | `10.10.1.40` | OT supervision API |
| `ot-maintenance` | `10.10.1.41` | SSH maintenance server and scripts |
| `robot-a-01` | `10.10.1.50` | Robot API |
| `robot-a-02` | `10.10.1.51` | Robot API |
| `robot-b-01` | `10.10.1.52` | Robot API |
| `hacking-intranet-server` | `10.10.1.100` | Internal test workstation |
| `client-robot-01` | `10.10.3.10` and `10.10.2.20` | External robot simulation |
| `client-robot-02` | `10.10.3.11` and `10.10.2.21` | External robot simulation |

## Published host ports

| Service | Host URL |
|---|---|
| Diagnostic server | `https://localhost:8443` |
| Gitea | `https://localhost:3000` |
| Jenkins | `https://localhost:8444` |
| phpLDAPadmin | `http://localhost:8088` |
| OT Supervision | `http://localhost:8090` |
| IT Services | `http://localhost:8083` |

## Quick start

```bash
cd mecarobotix-lab
docker compose up -d --build
```

Check status:

```bash
docker compose ps
```

Check logs:

```bash
docker compose logs -f diagnostic-server
```

Enter the internal test host:

```bash
docker compose exec hacking-intranet-server bash
```

From there, test internal DNS:

```bash
nslookup ci.mecarobotix.local 10.10.1.12
curl http://ot-supervision/robots
curl http://robot-a-01:8080/status
```

Stop the lab:

```bash
docker compose down
```

Delete volumes if you want a full reset:

```bash
docker compose down -v
```

## LDAP

Base DN:

```text
dc=mecarobotix,dc=local
```

Admin DN depends on the OpenLDAP image, but for Bitnami OpenLDAP use:

```text
cn=admin,dc=mecarobotix,dc=local
```

Configured groups are defined in `configs/ldap/bootstrap.ldif`.

## DNS

The internal DNS zone is:

```text
mecarobotix.local
```

Zone files are located in:

```text
configs/dns/
```

## Replacing the Python diagnostic server with the vulnerable binary

For the first deployment, `diagnostic-server` uses a Python/FastAPI placeholder.

Later, replace the content of:

```text
services/diagnostic-server/
```

with a Dockerfile that copies and launches the custom binary service.

The service should keep the same container name, IP and published port if possible:

```text
container: diagnostic-server
DMZ IP: 10.10.2.10
host port: 8080
container port: 80 or the binary listening port
```
