# MécaRobotix Vulnerable Infrastructure Design

This document isn't up to date with the fixed design of the maquette, containing detailed information about the vulnerable version.

## 1. Purpose of This Document

This document defines the initial infrastructure design for the MécaRobotix cybersecurity lab. The goal is to provide a clear and shared technical reference for the group before implementing the Docker-based environment.

This infrastructure represents the **initial/base architecture** of MécaRobotix. It is intentionally designed as a functional but weakly segmented environment, consistent with the project scenario: poor OT/IT isolation, internal services placed in a flat network, technical accounts, robot diagnostic services, and insufficient governance around access and secrets.

At this stage, the objective is **not yet to implement attacks or exploit vulnerabilities**. The objective is to define:

- Docker images and technologies to use.
- Services and ports per server.
- Network zones and IP ranges.
- Router/firewall components.
- DNS naming.
- LDAP structure.
- Users, groups, and permissions.
- Functional assumptions for the lab.

A later implementation phase may replace some placeholder Python services with a custom vulnerable binary, including a service vulnerable to a buffer overflow.

---

## 2. Project Context

MécaRobotix is a company specialized in the design, integration, and maintenance of industrial robots. These robots are deployed at client sites and communicate with MécaRobotix's diagnostic platform using technical accounts, API keys, and certificates.

The base scenario includes the following weaknesses:

- Poor separation between IT and OT environments.
- Maintenance scripts containing clear-text secrets.
- Shared technical accounts.
- No secrets management solution.
- Internal directory service but no IAG/IAM governance.
- Poorly documented service accounts.
- Excessively broad administrator access.
- Shared `root` account among technicians.
- CI/CD scripts embedding robot identifiers or credentials.
- No secret rotation.
- Weak traceability of sensitive actions.

The lab infrastructure must therefore allow the team to represent a working enterprise environment while keeping these design weaknesses visible.

---

## 3. High-Level Architecture

The lab is divided into three main areas:

1. **Client / External Robot Side**  
   Simulates robots deployed at client sites.

2. **Updates Network / DMZ**  
   Contains the diagnostic server exposed to external robots.

3. **Internal Flat Network**  
   Contains users, IT services, development services, databases, OT services, and internal robots in the same internal network.

```text
                          [External Robots / Client Sites]
                                      |
                                      | HTTPS / API / update channel
                                      v
                                  [Internet]
                                      |
                              Public IP / NAT
                                      |
                                [router-edge]
                                      |
                                 [firewall]
                                      |
                              [firewall-router]
                             /                 \
                            /                   \
              10.10.2.0/24                       10.10.1.0/24
          [Updates Network / DMZ]             [INTERNAL_FLAT_NET]
                    |                                  |
          [diagnostic-server]              Users / IT / DEV / OT / Robots
              10.10.2.10
                    |
                    +---- excessive access to internal network
```

---

## 4. Network Definition

### 4.1 Network Zones

| Network Name | CIDR Range | Purpose | Notes |
|---|---:|---|---|
| `updates_net` | `10.10.2.0/24` | Updates Network / DMZ | Hosts the diagnostic server exposed to external robots. |
| `internal_flat_net` | `10.10.1.0/24` | Internal flat network | Contains users, IT, DEV, OT, databases, and robots. |
| `client_robot_net` | `10.10.3.0/24` | External/client robot simulation | Simulates robots deployed at client sites. |


### 4.2 Gateways

| Network | Gateway IP | Provided By |
|---|---:|---|
| `updates_net` | `10.10.2.1` | `firewall-router` |
| `internal_flat_net` | `10.10.1.1` | `firewall-router` |
| `client_robot_net` | `10.10.3.1` | `firewall-router` or `router-edge` |

---

## 5. Router and Firewall Design

For the first implementation, a single container can represent the perimeter router and firewall functions.

### 5.1 Recommended Component

| Component | Suggested Technology | Function |
|---|---|---|
| `firewall-router` | Debian Bookworm + `iproute2` + `iptables`/`nftables` | Routing between lab networks, NAT, port forwarding, and firewall rules. |

### 5.2 Interfaces

| Interface | Connected Network | IP Address |
|---|---|---:|
| `eth0` | `client_robot_net` | `10.10.3.1` |
| `eth1` | `updates_net` | `10.10.2.1` |
| `eth2` | `internal_flat_net` | `10.10.1.1` |

### 5.3 Initial Functional Rules

At the first stage, the objective is connectivity, not hardening. The firewall rules can therefore be permissive.

| Traffic Flow | Initial Rule | Purpose |
|---|---|---|
| Client robots → diagnostic server | Allow HTTP/HTTPS/API traffic | Simulate external robots reaching the diagnostic platform. |
| Updates Network → Internal Flat Network | Allow broadly | Represents weak DMZ-to-internal filtering. |
| Internal Flat Network → Updates Network | Allow | Allows internal users/services to access the diagnostic server. |

---

## 6. Server Inventory

### 6.1 Full Server Table

| Zone | Host / Server | IP Address | Recommended Image / Technology | Services | Main Ports |
|---|---|---:|---|---|---:|
| Updates / DMZ | `diagnostic-server` | `10.10.2.10` | `python:3.11-slim` + FastAPI/Flask placeholder | Diagnostic API, robot updates, telemetry intake | `80`, `443`, `8080` |
| Internal | `ldap-server` | `10.10.1.10` | `bitnami/openldap` or `osixia/openldap` | LDAP directory | `389`, `636` |
| Internal | `phpldapadmin` | `10.10.1.11` | `osixia/phpldapadmin` | Web LDAP administration | `80` |
| Internal | `dns-server` | `10.10.1.12` | `ubuntu/bind9` or ISC BIND | Internal DNS | `53/tcp`, `53/udp` |
| Internal | `devops-server` | `10.10.1.20` | `gitea/gitea` | Git repositories | `3000`, `22` |
| Internal | `artifact-registry` | `10.10.1.23` or grouped with `devops-server` | `nginx:alpine`, MinIO, or simple HTTP server | Firmware artifacts | `8081` |
| Internal | `ci-server` | `10.10.1.21` | `jenkins/jenkins:lts-jdk17` or Woodpecker CI | CI/CD pipelines | `8080`, `50000` |
| Internal | `it-services` | `10.10.1.30` | `nginx:alpine`, Samba, or simple web app | File share, admin panel | `80`, `8080`, `445`, `139` |
| Internal | `db-internal` | `10.10.1.31` | `postgres:16` | Internal database | `5432` |
| Internal | `backup-log-server` | `10.10.1.33` | Debian/Alpine + rsyslog | Backups and basic syslog | `514/tcp`, `514/udp`, `22` |
| Internal | `ot-supervision` | `10.10.1.40` | `python:3.11-slim` + FastAPI/Flask | OT dashboard and supervision API | `8080`, `9000` |
| Internal | `ot-maintenance` | `10.10.1.41` | Debian Bookworm + OpenSSH | Maintenance scripts and SSH access | `22`, `8080` |
| Internal | `robot-a-01` | `10.10.1.50` | Custom robot API image | Robot API | `8080`, `22 optional` |
| Internal | `robot-a-02` | `10.10.1.51` | Custom robot API image | Robot API | `8080`, `22 optional` |
| Internal | `robot-b-01` | `10.10.1.52` | Custom robot API image | Robot API | `8080`, `22 optional` |
| Internal | `hacking-intranet-server` | `10.10.1.100` | Debian Bookworm tools or Kali | Internal testing host | No public port required |
| Client Site | `client-robot-01` | `10.10.3.10` | Custom robot client image | External robot simulation | `8080` |
| Client Site | `client-robot-02` | `10.10.3.11` | Custom robot client image | External robot simulation | `8080` |

---

## 7. Diagnostic Server

### 7.1 Role

The `diagnostic-server` represents MécaRobotix's diagnostic and update platform for robots deployed at client sites.

### 7.2 Initial Technology

For the architecture definition and first implementation, the service can be represented by:

```text
python:3.11-slim + FastAPI or Flask
```

Later, this placeholder may be replaced by a custom vulnerable binary running a service vulnerable to a buffer overflow.

### 7.3 Functional Endpoints

Suggested endpoints:

| Method | Endpoint | Purpose |
|---|---|---|
| `GET` | `/health` | Health check. |
| `POST` | `/api/robots/register` | Register a robot. |
| `POST` | `/api/robots/telemetry` | Receive robot telemetry. |
| `GET` | `/api/firmware/latest` | Provide latest firmware metadata. |
| `POST` | `/api/firmware/download` | Simulate firmware download. |

### 7.4 Ports

| Port | Use |
|---:|---|
| `80/tcp` | HTTP API. |
| `443/tcp` | Optional HTTPS simulation. |
| `8080/tcp` | Alternative app port if not using port 80. |

### 7.5 Exposure

In the real conceptual architecture:

```text
Public IP / NAT -> diagnostic-server in Updates Network
```

In the lab:

```text
Host port 8080 -> diagnostic-server port 80
```

Example external lab access:

```text
http://<university-server-ip>:8080
```

---

## 8. Internal Services

### 8.1 LDAP Server

| Item | Definition |
|---|---|
| Host | `ldap-server` |
| IP | `10.10.1.10` |
| Technology | OpenLDAP |
| Image | `bitnami/openldap` or `osixia/openldap` |
| Ports | `389`, `636` |

The LDAP server represents the internal directory. It stores users, groups, and service accounts.

### 8.2 phpLDAPadmin

| Item | Definition |
|---|---|
| Host | `phpldapadmin` |
| IP | `10.10.1.11` |
| Technology | phpLDAPadmin |
| Image | `osixia/phpldapadmin` |
| Ports | `80` |

phpLDAPadmin is used to visually manage the LDAP directory during the lab.

### 8.3 DNS Server

| Item | Definition |
|---|---|
| Host | `dns-server` |
| IP | `10.10.1.12` |
| Technology | BIND9 |
| Image | `ubuntu/bind9` or ISC BIND |
| Ports | `53/tcp`, `53/udp` |
| Internal Domain | `mecarobotix.local` |

### 8.4 DevOps Server

| Item | Definition |
|---|---|
| Host | `devops-server` |
| IP | `10.10.1.20` |
| Technology | Gitea |
| Image | `gitea/gitea` |
| Ports | `3000`, `22` |

Suggested repositories:

```text
firmware-robot-a
firmware-robot-b
robot-maintenance-scripts
deployment-tools
infrastructure-docs
```

### 8.5 CI Server

| Item | Definition |
|---|---|
| Host | `ci-server` |
| IP | `10.10.1.21` |
| Technology | Jenkins or Woodpecker CI |
| Recommended Image | `jenkins/jenkins:lts-jdk17` |
| Ports | `8080`, `50000` |

Suggested jobs:

```text
build-firmware-a
build-firmware-b
deploy-to-lab-robots
run-robot-tests
```

### 8.6 IT Services

| Item | Definition |
|---|---|
| Host | `it-services` |
| IP | `10.10.1.30` |
| Technologies | Nginx, Samba, or simple web app |
| Services | File share, internal admin panel |
| Ports | `80`, `8080`, `445`, `139` |

Suggested directories:

```text
/shared
/shared/admin
/shared/technical
/shared/maintenance
/shared/clients
/shared/backups
```

### 8.7 Internal Database

| Item | Definition |
|---|---|
| Host | `db-internal` |
| IP | `10.10.1.31` |
| Technology | PostgreSQL |
| Image | `postgres:16` |
| Port | `5432` |

Suggested databases:

```text
diagnostic_db
robot_inventory
robot_credentials
maintenance_history
client_data
```

Suggested tables:

```text
robots(id, name, type, ip_address, status, client_id)
clients(id, name, sector, contact)
robot_credentials(id, robot_type, username, api_key, cert_name)
maintenance_jobs(id, robot_id, technician, status, date)
firmware_versions(id, robot_type, version, artifact_url)
```

### 8.8 Backup and Log Server

| Item | Definition |
|---|---|
| Host | `backup-log-server` |
| IP | `10.10.1.33` |
| Technology | rsyslog + simple backup storage |
| Ports | `514/tcp`, `514/udp`, `22` |

This service centralizes basic logs and stores backups.

### 8.9 OT Supervision

| Item | Definition |
|---|---|
| Host | `ot-supervision` |
| IP | `10.10.1.40` |
| Technology | FastAPI/Flask placeholder |
| Ports | `8080`, `9000` |

Suggested endpoints:

| Method | Endpoint | Purpose |
|---|---|---|
| `GET` | `/health` | Health check. |
| `GET` | `/robots` | List robots. |
| `GET` | `/robots/{id}/status` | Get robot status. |
| `POST` | `/robots/{id}/restart` | Restart robot. |
| `POST` | `/robots/{id}/update` | Update robot firmware. |

### 8.10 OT Maintenance

| Item | Definition |
|---|---|
| Host | `ot-maintenance` |
| IP | `10.10.1.41` |
| Technology | Debian + OpenSSH |
| Ports | `22`, `8080 optional` |

Suggested file structure:

```text
/opt/maintenance/
├── update_robot.sh
├── restart_robot.sh
├── check_status.sh
├── deploy_firmware.sh
└── config/
    ├── robots.env
    └── robot_keys.env
```

### 8.11 Robot Servers

| Host | IP | Robot Type | Technology | Ports |
|---|---:|---|---|---:|
| `robot-a-01` | `10.10.1.50` | A | Custom FastAPI robot API | `8080`, `22 optional` |
| `robot-a-02` | `10.10.1.51` | A | Custom FastAPI robot API | `8080`, `22 optional` |
| `robot-b-01` | `10.10.1.52` | B | Custom FastAPI robot API | `8080`, `22 optional` |

Suggested endpoints:

| Method | Endpoint | Purpose |
|---|---|---|
| `GET` | `/health` | Health check. |
| `GET` | `/status` | Robot status. |
| `GET` | `/telemetry` | Robot telemetry. |
| `POST` | `/update-firmware` | Simulate firmware update. |
| `POST` | `/restart` | Restart robot. |

### 8.12 Hacking Intranet Server

| Item | Definition |
|---|---|
| Host | `hacking-intranet-server` |
| IP | `10.10.1.100` |
| Technology | Debian Bookworm tools or Kali |
| Role | Internal testing host simulating a compromised intranet machine |

Suggested tools:

```text
curl
wget
nmap
dnsutils
ldap-utils
postgresql-client
openssh-client
git
netcat-openbsd
python3
iputils-ping
traceroute
```

This host is not a production service. It is used to test internal connectivity and later to simulate post-compromise activity.

---

## 9. DNS Plan

### 9.1 Internal Domain

```text
mecarobotix.local
```

### 9.2 Internal DNS Records

| DNS Name | IP Address |
|---|---:|
| `ldap.mecarobotix.local` | `10.10.1.10` |
| `phpldapadmin.mecarobotix.local` | `10.10.1.11` |
| `dns.mecarobotix.local` | `10.10.1.12` |
| `git.mecarobotix.local` | `10.10.1.20` |
| `ci.mecarobotix.local` | `10.10.1.21` |
| `artifacts.mecarobotix.local` | `10.10.1.23` |
| `files.mecarobotix.local` | `10.10.1.30` |
| `admin.mecarobotix.local` | `10.10.1.30` |
| `db.mecarobotix.local` | `10.10.1.31` |
| `logs.mecarobotix.local` | `10.10.1.33` |
| `backup.mecarobotix.local` | `10.10.1.33` |
| `ot-supervision.mecarobotix.local` | `10.10.1.40` |
| `ot-maintenance.mecarobotix.local` | `10.10.1.41` |
| `robot-a-01.mecarobotix.local` | `10.10.1.50` |
| `robot-a-02.mecarobotix.local` | `10.10.1.51` |
| `robot-b-01.mecarobotix.local` | `10.10.1.52` |
| `hacking-intranet.mecarobotix.local` | `10.10.1.100` |
| `diag.mecarobotix.local` | `10.10.2.10` |

### 9.3 Public DNS Concept

For documentation purposes:

```text
diag.mecarobotix.com -> 203.0.113.10
```

In the lab, this can be simulated using:

```text
diag.mecarobotix.com -> university server IP or a temporary tunnel URL
```

---

## 10. LDAP Design

### 10.1 Base DN

```text
dc=mecarobotix,dc=local
```

### 10.2 Organizational Units

```text
ou=people,dc=mecarobotix,dc=local
ou=groups,dc=mecarobotix,dc=local
ou=services,dc=mecarobotix,dc=local
ou=robots,dc=mecarobotix,dc=local
```

### 10.3 Human Users

| User ID | Role | Main Group |
|---|---|---|
| `dev01` | Firmware developer | `developers` |
| `dev02` | Firmware developer | `developers` |
| `meca01` | Mechatronics engineer | `mechatronics` |
| `tech01` | Installation technician | `technicians` |
| `tech02` | Installation technician | `technicians` |
| `itadmin01` | IT administrator | `it_admins` |
| `itadmin02` | IT administrator | `it_admins` |
| `admin01` | Administrative staff | `administrative` |
| `sec01` | Security IT | `security_team` |

Example DN:

```text
uid=dev01,ou=people,dc=mecarobotix,dc=local
```

### 10.4 Service Accounts

| Service Account | Purpose |
|---|---|
| `svc_ci_robot_deploy` | Used by CI/CD to deploy firmware. |
| `svc_diagnostic_api` | Used by the diagnostic server to access internal APIs or DB. |
| `svc_robot_sync` | Used for robot synchronization. |
| `svc_backup` | Used by backup jobs. |
| `svc_ldap_bind` | Used by applications to query LDAP. |
| `svc_logs` | Used to send logs. |

Example DN:

```text
uid=svc_ci_robot_deploy,ou=services,dc=mecarobotix,dc=local
```

### 10.5 LDAP Groups

| Group | Intended Members | Purpose |
|---|---|---|
| `developers` | `dev01`, `dev02` | Firmware development. |
| `mechatronics` | `meca01` | Technical design and documentation. |
| `technicians` | `tech01`, `tech02` | Robot installation and maintenance. |
| `it_admins` | `itadmin01`, `itadmin02` | System administration. |
| `administrative` | `admin01` | Administrative access. |
| `security_team` | `sec01` | Log review and security oversight. |
| `robot_admins` | `tech01`, `tech02`, `svc_ci_robot_deploy` | Robot administration. |
| `service_accounts` | all `svc_*` accounts | Technical accounts. |
| `ci_users` | `dev01`, `dev02`, `svc_ci_robot_deploy` | CI/CD users. |
| `ot_users` | `technicians`, `robot_admins` | OT-related access. |

Example DN:

```text
cn=developers,ou=groups,dc=mecarobotix,dc=local
```

---

## 11. Functional Permission Model

The permissions below define the first functional state of the lab. They are intentionally broad enough to support the weak base architecture.

### 11.1 Gitea / DevOps Server

| Group | Permission |
|---|---|
| `developers` | Read/write firmware repositories. |
| `ci_users` | Read repositories and trigger CI jobs. |
| `technicians` | Read maintenance scripts. |
| `it_admins` | Admin access. |
| `security_team` | Read-only access. |

### 11.2 CI/CD Server

| Group or Account | Permission |
|---|---|
| `developers` | Execute build and test pipelines. |
| `svc_ci_robot_deploy` | Deploy firmware to lab robots. |
| `it_admins` | Admin access. |
| `security_team` | Read logs. |

### 11.3 File Share

| Directory | Intended Access |
|---|---|
| `/shared/admin` | `administrative`, `it_admins` |
| `/shared/technical` | `developers`, `mechatronics`, `technicians` |
| `/shared/maintenance` | `technicians`, `it_admins` |
| `/shared/clients` | `administrative`, `technicians` |
| `/shared/backups` | `it_admins`, `svc_backup` |

### 11.4 Internal Database

| DB User | Used By | Purpose |
|---|---|---|
| `diagnostic_app` | `diagnostic-server` | Access diagnostic and robot data. |
| `ci_app` | `ci-server` | Read firmware and robot deployment data. |
| `ot_supervision_app` | `ot-supervision` | Read robot inventory and statuses. |
| `backup_app` | `backup-log-server` | Perform backups. |
| `admin_db` | IT admins | Database administration. |

### 11.5 OT Supervision

| Group | Permission |
|---|---|
| `technicians` | View robots and execute basic actions. |
| `robot_admins` | Administer robot operations. |
| `it_admins` | Administer platform. |
| `developers` | View and test. |
| `security_team` | Read logs. |

---

## 12. Host Ports to Expose on the Docker Host

Not every internal service should be exposed on the Docker host. The following ports are useful for administration and demonstrations.

| Service | Host Port | Container Port | Purpose |
|---|---:|---:|---|
| `diagnostic-server` | `8080` | `80` | Simulate public diagnostic endpoint. |
| `devops-server` / Gitea | `3000` | `3000` | Web access to Git repositories. |
| Gitea SSH | `2222` | `22` | Git over SSH if needed. |
| `ci-server` / Jenkins | `8081` | `8080` | Web access to CI/CD. |
| `phpldapadmin` | `8088` | `80` | Web LDAP administration. |
| `ot-supervision` | `8090` | `8080` | OT supervision demo. |
| `artifact-registry` | `8082` | `8081` | Firmware artifact access. |
| `it-services` | `8083` | `80` or `8080` | File-share/admin panel demo. |

Services that should normally remain internal:

| Service | Reason |
|---|---|
| `db-internal` | Database should only be reached by internal services. |
| `ldap-server` | LDAP is queried by internal apps. |
| `dns-server` | Internal name resolution only. |
| `robots` | Robot APIs should be accessed internally or through lab paths. |
| `backup-log-server` | Internal logs and backups. |

---

## 13. Implementation Notes

### 13.1 Recommended Docker Approach

The lab should be implemented with Docker Compose.

Recommended structure:

```text
mecarobotix-lab/
├── docker-compose.yml
├── .env
├── configs/
│   ├── bind9/
│   ├── ldap/
│   ├── gitea/
│   ├── jenkins/
│   └── rsyslog/
├── services/
│   ├── diagnostic-server/
│   ├── ot-supervision/
│   ├── robot-api/
│   └── ot-maintenance/
├── data/
│   ├── postgres/
│   ├── gitea/
│   ├── jenkins/
│   └── ldap/
└── backups/
```

### 13.2 Placeholder Services

For the first working version, several services can be represented by simple Python APIs:

| Service | Placeholder Technology |
|---|---|
| `diagnostic-server` | FastAPI/Flask |
| `ot-supervision` | FastAPI/Flask |
| `robot-a-01` | FastAPI/Flask |
| `robot-a-02` | FastAPI/Flask |
| `robot-b-01` | FastAPI/Flask |
| `client-robot-01` | FastAPI/Flask |
| `client-robot-02` | FastAPI/Flask |

Later, the diagnostic or robot service can be replaced by a custom vulnerable binary.

### 13.3 Future Vulnerable Binary Integration

The current architecture describes the diagnostic server as a Python-based placeholder. However, the final lab may run a custom binary implementing a vulnerable network service.

Recommended integration strategy:

```text
Phase 1: Python placeholder service for connectivity and API testing.
Phase 2: Replace or complement the placeholder with the custom vulnerable binary.
Phase 3: Keep the same network position, IP, and exposure path for consistency.
```

The binary should keep the same conceptual role:

```text
External robots / client sites -> diagnostic-server -> internal network
```

---

## 14. Components Deferred for Later Phases

The following components are intentionally not included in the first working version:

| Deferred Component | Reason |
|---|---|
| Vault | Will be part of the corrected architecture or secrets management improvement. |
| Keycloak / full IAM | Useful later to represent IAM/IAG improvements. |
| Wazuh / ELK | Too heavy for the first version. Basic syslog is enough initially. |
| pfSense / OPNsense | Better as a VM than Docker; not necessary for first version. |
| Active Directory | More complex than needed; LDAP is enough for this lab. |
| IDS/IPS | Can be added in a later detection phase. |
| Full HTTPS / PKI | Can be added later if needed. |

---

## 15. Final Initial Lab Definition

### 15.1 Networks

```text
updates_net        10.10.2.0/24
internal_flat_net  10.10.1.0/24
client_robot_net   10.10.3.0/24
```

### 15.2 Core Infrastructure

```text
firewall-router       10.10.1.1 / 10.10.2.1 / 10.10.3.1
diagnostic-server     10.10.2.10
ldap-server           10.10.1.10
phpldapadmin          10.10.1.11
dns-server            10.10.1.12
devops-server         10.10.1.20
ci-server             10.10.1.21
artifact-registry     10.10.1.23
it-services           10.10.1.30
db-internal           10.10.1.31
backup-log-server     10.10.1.33
ot-supervision        10.10.1.40
ot-maintenance        10.10.1.41
robot-a-01            10.10.1.50
robot-a-02            10.10.1.51
robot-b-01            10.10.1.52
hacking-intranet      10.10.1.100
client-robot-01       10.10.3.10
client-robot-02       10.10.3.11
```

### 15.3 Main Exposed Lab Services

```text
Diagnostic API:      http://<docker-host>:8080
Gitea:               http://<docker-host>:3000
Jenkins:             http://<docker-host>:8081
phpLDAPadmin:        http://<docker-host>:8088
OT Supervision:      http://<docker-host>:8090
```

---

