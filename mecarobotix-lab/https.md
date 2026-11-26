# HTTPS / TLS Migration 

This document details the transition from the vulnerable maquette to the version with a local CA, allowing the use of HTTPS / TLS. Note that it doesn't take into account the new segmented network structure.

## Step 1 - Inventory of Current Insecure Communications

Goal: identify every flow that used HTTP, LDAP without TLS, PostgreSQL without TLS, or any other insecure protocol before introducing certificates and HTTPS.

### Relevant Networks

| Network | Subnet | Purpose |
| --- | --- | --- |
| `internal_flat_net` | `10.10.1.0/24` | Internal IT/OT services |
| `updates_net` | `10.10.2.0/24` | Diagnostics and updates |
| `client_robot_net` | `10.10.3.0/24` | Simulated external client robots |

### Web/API Services

| Service | Internal Port | Current Role | Risk |
| --- | ---: | --- | --- |
| `diagnostic-server` | `443` | Diagnostic, telemetry, and firmware API over HTTPS | Critical: receives robot data and returns firmware URLs |
| `robot-a-01`, `robot-a-02`, `robot-b-01` | `8080` / `8443` | Robot API for status, firmware, restart, and config | Critical: operational actions on robots |
| `client-robot-01`, `client-robot-02` | `8080` / `8443` | External client robot API | Critical: external robot path to diagnostics |
| `devops-server` | `3000` | Gitea over HTTPS | High: repositories, releases, webhooks, credentials |
| `ci-server` | `8443` | Jenkins over HTTPS | High: jobs, logs, secrets, webhooks |
| `artifact-registry` | `443` | Nginx firmware artifacts over HTTPS | High: firmware update channel |
| `ot-supervision` | `80` | Operational dashboard | High: operational UI for robots |
| `it-services` | `80` | Internal file server | Medium/high: internal file downloads |
| `backup-log-server` | `80` | Internal backup/log API | Medium: logs and backup data |
| `phpldapadmin` | `80` | LDAP administration UI | High: admin panel without HTTPS |

### Main HTTP/HTTPS Flows

| Source | Destination | URL / Pattern | Files | Priority |
| --- | --- | --- | --- | --- |
| Internal robots | `diagnostic-server` | `https://diagnostic-server/api/telemetry` | `docker-compose.yml`, `services/robot-api/app.py` | P0 |
| Client robots | `diagnostic-server` | `https://10.10.2.10/api/telemetry` | `docker-compose.yml` | P0 |
| ESP32 firmware | `diagnostic-server` | `DIAGNOSTIC_SERVER_DEFAULT_URL` over HTTPS with `WiFiClientSecure`, internal CA, and client certificate | `data/firmware/include/config.h`, `Firmware/src/diagnostic_client.cpp` | P0 |
| `diagnostic-server` | `artifact-registry` | `https://artifact-registry/firmware/robot-*-latest.bin` | `services/diagnostic-server/app.c`, firmware mirrors | P0 |
| `ot-maintenance` | Robots | `https://<robot>:8443/status` | `services/ot-maintenance/maintenance/lib/common.sh`, `check_status.sh` | P0 |
| `ot-maintenance` | Robots | `https://<robot>:8443/update-firmware` | `services/ot-maintenance/maintenance/update_robot.sh` | P0 |
| `ot-maintenance` | Robots | `https://<robot>:8443/restart` | `services/ot-maintenance/maintenance/restart_robot.sh` | P0 |
| `ot-maintenance` | Robots | `https://<robot>:8443/diagnostic-server` | `services/ot-maintenance/maintenance/change_diagnostic_server.sh` | P0 |
| `ot-maintenance` | Robots | `https://<robot>:8443/debug/config` | `services/ot-maintenance/maintenance/collect_debug_config.sh` | P0 |
| `ot-maintenance` | `diagnostic-server` | `https://diagnostic-server/api/firmware/latest` | `services/ot-maintenance/maintenance/request_latest_firmware.sh`, `config/secrets.env` | P0 |
| `ot-supervision` | Robots | `https://robot-a-01:8443`, etc. | `services/ot-supervision/app.py` | P0 |
| `ci-server` | Gitea | `https://devops-server:3000` | `services/ci-server/ci-scripts/ci-secrets.env` | P1 |
| `ci-server` | Gitea API | `https://devops-server:3000/api/v1` | `services/ci-server/ci-scripts/ci-secrets.env`, `sync_gitea_release_to_artifact_registry.sh` | P1 |
| `ci-server` | `artifact-registry` | `https://artifact-registry` | `services/ci-server/ci-scripts/ci-secrets.env` | P1 |
| `ci-server` | `diagnostic-server` | `https://diagnostic-server` | CI scripts | P1 |
| Gitea webhook | Jenkins | `https://ci-server:8443/job/...` | `scripts/init-gitea.sh` | P1 |
| Smoke tests | Several services | HTTPS/mTLS validation commands | `scripts/smoke_tests.sh` | P3 |

### Non-HTTP Protocols

| Source | Destination | Current Protocol | Files | Priority |
| --- | --- | --- | --- | --- |
| `it-services` | `ldap-server` | `ldaps://ldap-server:1636` | `docker-compose.yml`, `services/it-services/entrypoint.sh` | P2 |
| `phpldapadmin` | `ldap-server` | LDAPS to `ldap-server:1636` | `docker-compose.yml` | P2 |
| Internal services | `db-internal` | PostgreSQL with TLS on `5432` | `docker-compose.yml`, maintenance config | P2 |
| Employees/robots | `it-services` | FTP without TLS | `services/it-services/vsftpd.conf`, `docker-compose.yml` | P3 |
| Employees/robots | `it-services` | SMB without guaranteed transport encryption | `services/it-services/smb.conf`, `docker-compose.yml` | P3 |

### Secrets in URLs or Query Strings

HTTPS encrypts transport, but URLs can still appear in logs, browser history, shell history, and traces. Sensitive values were moved out of query strings.

| File | Current State |
| --- | --- |
| `services/ot-maintenance/maintenance/request_latest_firmware.sh` | Uses mTLS; query keeps only `robot_type` |
| `services/ot-maintenance/maintenance/update_robot.sh` | Uses mTLS toward robots |
| `services/ot-maintenance/maintenance/restart_robot.sh` | Uses `X-Robot-Api-Key` and `X-Maintenance-Operator` headers |
| `services/ot-maintenance/maintenance/change_diagnostic_server.sh` | Uses `X-Ldap-Admin-Dn` and `X-Ldap-Password` headers |
| `services/ot-maintenance/maintenance/collect_debug_config.sh` | Uses mTLS and `X-Postgres-Password` |
| `services/ci-server/ci-scripts/robot_http_maintenance.sh` | Uses headers and disables `set -x` around sensitive `curl` calls |
| `services/ci-server/ci-scripts/sync_gitea_release_to_artifact_registry.sh` | Uses headers and disables `set -x` around sensitive `curl` calls |
| `scripts/init-gitea.sh` | Webhook has no credentials in URL; uses `authorization_header` |

### Migration Priorities

- P0: Critical OT flows: robots, `diagnostic-server`, `ot-maintenance`, `ot-supervision`, firmware.
- P1: DevOps/CI flows: Gitea, Jenkins, webhooks, artifact registry.
- P2: Identity/data services: LDAPS and PostgreSQL TLS.
- P3: Auxiliary services, smoke tests, and legacy protocols.

## Step 2 - Internal Lab CA

A reproducible PKI generator was added.

| File | Purpose |
| --- | --- |
| `scripts/generate-pki.sh` | Creates the internal CA, service certificates, and client certificates |
| `services/pki-init/Dockerfile` | Minimal OpenSSL image for generating PKI through Compose |
| `data/pki/README.md` | Documents the expected PKI layout |
| `.gitignore` | Prevents generated private keys and certificates from being committed |

The CA is generated under:

```text
data/pki/ca/ca.crt
data/pki/ca/ca.key
```

The private CA key must not be shared with services. Services only mount the public CA certificate `ca.crt`.

## Step 3 - TLS Certificates per Service

The `pki-init` service generates host certificates under:

```text
data/pki/services/<service>/tls.crt
data/pki/services/<service>/tls.key
data/pki/services/<service>/tls-chain.crt
data/pki/services/<service>/san.cnf
```

Services with generated server certificates:

- `firewall-router`
- `diagnostic-server`
- `ldap-server`
- `phpldapadmin`
- `dns-server`
- `devops-server`
- `ci-server`
- `artifact-registry`
- `it-services`
- `db-internal`
- `backup-log-server`
- `ot-supervision`
- `ot-maintenance`
- `robot-a-01`
- `robot-a-02`
- `robot-b-01`
- `client-robot-01`
- `client-robot-02`
- `mrx-esp32-001`
- `hacking-intranet-server`

Client certificates are generated separately:

```text
data/pki/clients/<client>/client.crt
data/pki/clients/<client>/client.key
data/pki/clients/<client>/client-chain.crt
data/pki/clients/<client>/client.cnf
```

Clients with generated certificates:

- `robot-a-01`
- `robot-a-02`
- `robot-b-01`
- `client-robot-01`
- `client-robot-02`
- `mrx-esp32-001`
- `ot-maintenance`
- `ot-supervision`
- `ci-server`

## Step 4 - Certificate SANs

Each certificate is generated with DNS and/or IP SANs.

| Service | Relevant SANs |
| --- | --- |
| `diagnostic-server` | `diagnostic-server`, `diagnostic.mecarobotix.local`, `10.10.1.110`, `10.10.2.10`, `localhost`, `127.0.0.1` |
| `devops-server` | `devops-server`, `git.mecarobotix.local`, `localhost`, `10.10.1.20`, `127.0.0.1` |
| `ci-server` | `ci-server`, `jenkins.mecarobotix.local`, `localhost`, `10.10.1.21`, `127.0.0.1` |
| `artifact-registry` | `artifact-registry`, `artifacts.mecarobotix.local`, `10.10.1.23` |
| `robot-a-01` | `robot-a-01`, `robot-a-01.mecarobotix.local`, `10.10.1.50` |
| `client-robot-01` | `client-robot-01`, `client-robot-01.mecarobotix.local`, `10.10.3.10` |
| `mrx-esp32-001` | `mrx-esp32-001`, `mrx-esp32-001.mecarobotix.local` |

To inspect generated SANs:

```bash
openssl x509 -in data/pki/services/diagnostic-server/tls.crt -noout -text | grep -A2 "Subject Alternative Name"
```

## Step 5 - Public CA Distribution

Common CA-related variables were added to Compose:

```yaml
SSL_CERT_FILE: /etc/mecarobotix/pki/ca/ca.crt
REQUESTS_CA_BUNDLE: /etc/mecarobotix/pki/ca/ca.crt
CURL_CA_BUNDLE: /etc/mecarobotix/pki/ca/ca.crt
GIT_SSL_CAINFO: /etc/mecarobotix/pki/ca/ca.crt
NODE_EXTRA_CA_CERTS: /etc/mecarobotix/pki/ca/ca.crt
LDAPTLS_CACERT: /etc/mecarobotix/pki/ca/ca.crt
PGSSLROOTCERT: /etc/mecarobotix/pki/ca/ca.crt
```

Clients mount:

```text
./data/pki/ca:/etc/mecarobotix/pki/ca:ro
```

TLS-serving services mount their own certificate under:

```text
/etc/mecarobotix/tls
```

Generate the PKI from the project root:

```bash
sudo docker compose up --build pki-init
```

Or directly from the host:

```bash
PKI_DIR=data/pki ./scripts/generate-pki.sh
```

Regenerate from scratch:

```bash
FORCE_PKI_REGENERATE=1 PKI_DIR=data/pki ./scripts/generate-pki.sh
```

## Step 6 - HTTPS on `diagnostic-server`

`diagnostic-server` now terminates TLS with `nginx` using:

```text
/etc/mecarobotix/tls/tls-chain.crt
/etc/mecarobotix/tls/tls.key
```

The C backend listens internally on `127.0.0.1:8080`. `nginx` requires client certificates and forwards internal mTLS headers:

```text
X-MTLS-Verify
X-MTLS-Subject-DN
X-MTLS-Issuer-DN
X-MTLS-Serial
X-MTLS-Fingerprint
```

Secure endpoints:

```text
https://diagnostic-server
https://10.10.2.10
https://10.10.1.110
https://localhost:8443
```

Host validation:

```bash
curl --cacert data/pki/ca/ca.crt \
  --cert data/pki/clients/ci-server/client-chain.crt \
  --key data/pki/clients/ci-server/client.key \
  https://localhost:${DIAGNOSTIC_HTTPS_HOST_PORT:-8443}/health
```

Legacy HTTP is disabled for `diagnostic-server`: `ENABLE_LEGACY_HTTP=false`.

## Step 7 - Robots Consuming `diagnostic-server` over HTTPS

Internal robots use:

```text
DIAGNOSTIC_URL=https://diagnostic-server/api/telemetry
```

External client robots use the update-network IP:

```text
DIAGNOSTIC_URL=https://10.10.2.10/api/telemetry
```

Python `requests` validates certificates using:

```text
REQUESTS_CA_BUNDLE=/etc/mecarobotix/pki/ca/ca.crt
```

Robots also present their own client certificate when calling `diagnostic-server`.

## Step 8 - HTTPS on Robot APIs

The `services/robot-api` image now starts:

- Main HTTPS endpoint on `8443`.
- Internal app bound to loopback.
- Legacy HTTP can be kept or disabled with `ENABLE_LEGACY_HTTP`.

Each robot uses:

```text
/etc/mecarobotix/tls/tls-chain.crt
/etc/mecarobotix/tls/tls.key
```

Validation from a container with CA and client certificate mounted:

```bash
curl --cacert /etc/mecarobotix/pki/ca/ca.crt \
  --cert /etc/mecarobotix/client-tls/client-chain.crt \
  --key /etc/mecarobotix/client-tls/client.key \
  https://robot-a-01:8443/status
```

Expected result includes:

```json
"authorized_client":"ot-maintenance"
```

## Step 9 - HTTPS on `artifact-registry`

`artifact-registry` serves firmware artifacts through Nginx over TLS on `443`.

Certificate files:

```text
/etc/mecarobotix/tls/tls-chain.crt
/etc/mecarobotix/tls/tls.key
```

Nginx configuration:

```text
configs/artifact-registry/default.conf
```

Internal firmware URLs:

```text
https://artifact-registry/firmware/robot-a-latest.bin
https://artifact-registry/firmware/robot-b-latest.bin
```

Validation:

```bash
curl --cacert /etc/mecarobotix/pki/ca/ca.crt \
  https://artifact-registry/firmware/robot-a-latest.bin \
  -o /tmp/robot-a-latest.bin
```

Consumers now use HTTPS:

- `diagnostic-server` returns `artifact_url` with `https://artifact-registry/...`.
- CI uses `ARTIFACT_REGISTRY_URL=https://artifact-registry`.

## Step 10 - HTTPS on Jenkins / `ci-server`

`ci-server` terminates TLS using:

```text
/etc/mecarobotix/tls/tls-chain.crt
/etc/mecarobotix/tls/tls.key
```

Jenkins listens internally on HTTP, while the public service endpoint is:

```text
https://ci-server:8443
https://localhost:8444
```

Validation:

```bash
curl --cacert data/pki/ca/ca.crt \
  -u jenkins_admin:Admin123! \
  https://localhost:8444/job/sync-gitea-release-to-artifact-registry/api/json
```

Consumers use:

- `JENKINS_URL=https://ci-server:8443`
- Gitea webhooks pointing to `https://ci-server:8443/job/...`
- Jenkins root URL set to `https://ci-server:8443/`

## Step 11 - HTTPS on Gitea / `devops-server`

`devops-server` serves Gitea over native HTTPS on `3000`.

Relevant Compose variables:

```text
GITEA__server__PROTOCOL=https
GITEA__server__HTTP_PORT=3000
GITEA__server__CERT_FILE=/etc/mecarobotix/tls/tls-chain.crt
GITEA__server__KEY_FILE=/etc/mecarobotix/tls/tls.key
```

Endpoints:

```text
https://devops-server:3000
https://localhost:3000
```

Validation:

```bash
curl --cacert data/pki/ca/ca.crt https://localhost:3000/api/healthz
```

Consumers now use:

- `GITEA_URL=https://devops-server:3000`
- `GITEA_API_URL=https://devops-server:3000/api/v1`
- `gitea-init` clones and pushes firmware over HTTPS.
- CI normalizes generated `https://localhost:3000/...` assets to `https://devops-server:3000/...`.

## Step 12 - LDAPS on `ldap-server`

`ldap-server` keeps OpenLDAP listening internally on `127.0.0.1:1389`. A sidecar proxy in the same network namespace exposes LDAPS on:

```text
ldaps://ldap-server:1636
```

The proxy terminates TLS with the LDAP service certificate:

```text
/etc/mecarobotix/tls/tls-chain.crt
/etc/mecarobotix/tls/tls.key
```

LDAP clients use:

```text
LDAPTLS_CACERT=/etc/mecarobotix/pki/ca/ca.crt
```

Consumers:

- `it-services` uses `LDAP_URL=ldaps://ldap-server:1636`.
- `services/it-services/entrypoint.sh` uses LDAPS by default.
- `phpldapadmin` connects to `ldaps://ldap-server:1636`.

`ldap-server` is built from `services/ldap-server/Dockerfile` so it includes `ldap-utils` for validation.

Validation:

```bash
docker compose exec ldap-server bash -lc '
LDAPTLS_CACERT=/etc/mecarobotix/pki/ca/ca.crt \
ldapwhoami -x -H ldaps://ldap-server:1636 \
  -D "cn=admin,dc=mecarobotix,dc=local" \
  -w "Admin123!"
'
```

Expected result:

```text
dn:cn=admin,dc=mecarobotix,dc=local
```

## Step 13 - TLS on PostgreSQL / `db-internal`

`db-internal` runs PostgreSQL with native TLS on `5432`.

Runtime files:

```text
/var/lib/postgresql/tls/server.crt
/var/lib/postgresql/tls/server.key
/etc/mecarobotix/pki/ca/ca.crt
```

Relevant PostgreSQL options:

```text
ssl=on
ssl_cert_file=/var/lib/postgresql/tls/server.crt
ssl_key_file=/var/lib/postgresql/tls/server.key
ssl_ca_file=/etc/mecarobotix/pki/ca/ca.crt
hba_file=/etc/postgresql/pg_hba.conf
```

`configs/postgres/pg_hba.conf` forces network TLS:

```text
hostssl all all 0.0.0.0/0 scram-sha-256
hostssl all all ::/0 scram-sha-256
hostnossl all all 0.0.0.0/0 reject
hostnossl all all ::/0 reject
```

Validation:

```bash
docker compose exec db-internal bash -lc '
PGPASSWORD="Admin123!" psql \
"host=db-internal port=5432 dbname=mecarobotix user=admin_db sslmode=verify-full sslrootcert=/etc/mecarobotix/pki/ca/ca.crt" \
-c "select ssl from pg_stat_ssl where pid = pg_backend_pid();"
'
```

Expected result: `t`.

Negative test:

```bash
docker compose exec db-internal bash -lc '
PGPASSWORD="Admin123!" psql \
"host=db-internal port=5432 dbname=mecarobotix user=admin_db sslmode=disable" \
-c "select 1;"
'
```

Expected result: connection rejected.

## Step 14 - Secrets Removed from Query Strings

Sensitive endpoints no longer expect secrets in URLs. Where mTLS exists, identity comes from the client certificate. Remaining secrets are passed through headers.

| Destination | Mechanism | Purpose |
| --- | --- | --- |
| `diagnostic-server` | mTLS client certificate | Authentication for `/api/*` |
| Robots | mTLS client certificate and selected headers | Firmware operations, debug config, restart/config changes |
| LDAP operations | `X-Ldap-Admin-Dn`, `X-Ldap-Password` | Maintenance actions that modify diagnostic URL |
| PostgreSQL debug operation | `X-Postgres-Password` | Lab-only debug config export |
| Jenkins/Gitea webhook | Header-based auth | CI trigger authentication |

Current behavior:

- `diagnostic-server` validates `/api/*` through identity propagated by `nginx`.
- `robot-api` validates sensitive robot actions through mTLS identity or specific maintenance headers.
- `ot-maintenance`, `ot-supervision`, and CI present client certificates.
- Gitea seed uses a remote URL without embedded credentials and passes `http.extraHeader=Authorization: Basic ...` only during `git push`.
- Simulated firmware uses a client certificate when calling `diagnostic-server`.

Validation:

```bash
docker compose exec ot-maintenance bash -lc '
curl -fsS \
  --cert "$CLIENT_TLS_CERT_FILE" \
  --key "$CLIENT_TLS_KEY_FILE" \
  "https://diagnostic-server/api/firmware/latest?robot_type=A"
'
```

A request without a client certificate must fail.

## Step 15 - Client Certificates for mTLS

Client certificates are separate from service/server certificates.

Layout:

```text
data/pki/clients/<client>/client.crt
data/pki/clients/<client>/client.key
data/pki/clients/<client>/client-chain.crt
data/pki/clients/<client>/client.cnf
```

These certificates use:

```text
extendedKeyUsage = clientAuth
```

Services mount client material under:

```text
/etc/mecarobotix/client-tls
```

Standard variables:

```text
CLIENT_TLS_CERT_FILE=/etc/mecarobotix/client-tls/client-chain.crt
CLIENT_TLS_KEY_FILE=/etc/mecarobotix/client-tls/client.key
```

Validate EKU:

```bash
openssl x509 -in data/pki/clients/robot-a-01/client.crt -noout -subject -ext extendedKeyUsage
openssl x509 -in data/pki/clients/ot-maintenance/client.crt -noout -subject -ext extendedKeyUsage
openssl x509 -in data/pki/clients/ot-supervision/client.crt -noout -subject -ext extendedKeyUsage
openssl x509 -in data/pki/clients/ci-server/client.crt -noout -subject -ext extendedKeyUsage
```

Expected result: `TLS Web Client Authentication`.

## Step 16 - mTLS Certificates inside ESP32 Firmware

The ESP32 firmware can present a client certificate when connecting over HTTPS and can also expose its local API over HTTPS with mTLS.

ESP32 PKI material:

```text
data/pki/clients/mrx-esp32-001/client.crt
data/pki/clients/mrx-esp32-001/client.key
data/pki/clients/mrx-esp32-001/client-chain.crt
data/pki/services/mrx-esp32-001/tls.crt
data/pki/services/mrx-esp32-001/tls.key
data/pki/services/mrx-esp32-001/tls-chain.crt
```

Exporter:

```text
scripts/export-esp32-pki-material.sh
```

Generated headers:

```text
Firmware/include/pki_material.h
data/firmware/include/pki_material.h
```

Header constants:

```text
MECAROBOTIX_CA_CERT
ROBOT_CLIENT_CERT
ROBOT_CLIENT_KEY
ROBOT_SERVER_CERT
ROBOT_SERVER_KEY
```

`pki_material.h` is ignored by Git because it contains ESP32 private keys.

Regenerate:

```bash
cd mecarobotix-lab
PKI_DIR=data/pki ./scripts/generate-pki.sh
ESP32_CLIENT_NAME=mrx-esp32-001 PKI_DIR=data/pki ./scripts/export-esp32-pki-material.sh
```

Firmware changes:

- `Firmware/src/diagnostic_client.cpp` uses `WiFiClientSecure`.
- The client configures `setCACert`, `setCertificate`, and `setPrivateKey`.
- `Firmware/src/robot_api.cpp` keeps legacy HTTP on `80`.
- `Firmware/src/robot_api.cpp` adds HTTPS+mTLS on `8443` using mbedTLS directly.
- Informational routes accept any valid client certificate signed by the CA.
- Operational routes require the CN to be listed in `ROBOT_MTLS_MANAGEMENT_CLIENTS`.

Compile:

```bash
cd ../Firmware
platformio run
```

Post-flash validation:

```bash
curl --resolve mrx-esp32-001:8443:<ESP32_IP> \
  --cacert mecarobotix-lab/data/pki/ca/ca.crt \
  --cert mecarobotix-lab/data/pki/clients/ot-maintenance/client-chain.crt \
  --key mecarobotix-lab/data/pki/clients/ot-maintenance/client.key \
  https://mrx-esp32-001:8443/health
```

Use `--resolve` so `curl` connects to the real ESP32 IP while validating the certificate against the hostname `mrx-esp32-001`.

## Step 17 - mTLS on Critical Flows

mTLS is enabled on lab-controlled TLS terminators.

| Flow | State |
| --- | --- |
| Robots -> `diagnostic-server` | Client presents certificate; `diagnostic-server` requires client certificate |
| `ot-maintenance` -> Robots | `curl` presents client certificate; robots require client certificate |
| `ot-supervision` -> Robots | `requests` presents client certificate; robots require client certificate |
| `ci-server` -> `diagnostic-server` | CI presents the `ci-server` client certificate |
| `ci-server` -> Robots | CI presents the `ci-server` client certificate |
| ESP32 -> `diagnostic-server` | ESP32 presents embedded client certificate |
| Clients -> ESP32 | ESP32 validates client certificates against the internal CA |

Client behavior:

- Python robots use `requests(..., cert=(CLIENT_TLS_CERT_FILE, CLIENT_TLS_KEY_FILE))`.
- `ot-supervision` uses its cert/key pair when calling robots.
- `ot-maintenance` automatically adds `--cert` and `--key` in its safe curl wrappers.
- CI scripts add `--cert` and `--key` when calling `diagnostic-server` and robots.
- ESP32 uses `WiFiClientSecure` with CA, client certificate, and private key.

## Step 18 - mTLS Identity with Nginx and No Diagnostic Token

`diagnostic-server` and `robot-api` no longer rely on `socat` for HTTPS termination. They use `nginx`, which:

- requires client certificates when `ENABLE_MTLS=true`;
- validates them against `/etc/mecarobotix/pki/ca/ca.crt`;
- forwards internal identity headers to the backend.

The legacy `DIAGNOSTIC_ACCESS_TOKEN` was removed from mTLS flows.

Current authorization:

- `diagnostic-server` authorizes `/api/*` when `X-MTLS-Verify=SUCCESS`, the CN is registered, and the CN is not revoked.
- Registered clients are checked under `/etc/mecarobotix/pki/clients/<CN>/client.crt`.
- `diagnostic-server` mounts the registry from `./data/pki/clients:/etc/mecarobotix/pki/clients:ro`.
- CN values are sanitized before path construction; only letters, numbers, `.`, `_`, and `-` are accepted.
- Robots authorize operational routes such as `/update-firmware` and `/debug/config` when the CN is listed in `ROBOT_MTLS_MANAGEMENT_CLIENTS`.
- `ci-server`, `ot-maintenance`, `ot-supervision`, Python robots, and ESP32 no longer send `Authorization: Bearer ...` for these endpoints.

Validation:

```bash
curl --cacert data/pki/ca/ca.crt \
  --cert data/pki/clients/ci-server/client-chain.crt \
  --key data/pki/clients/ci-server/client.key \
  "https://localhost:8443/api/firmware/latest?robot_type=A"

curl --cacert data/pki/ca/ca.crt \
  "https://localhost:8443/api/firmware/latest?robot_type=A"

curl --cacert data/pki/ca/ca.crt \
  --cert data/pki/services/diagnostic-server/tls-chain.crt \
  --key data/pki/services/diagnostic-server/tls.key \
  "https://localhost:8443/api/firmware/latest?robot_type=A"
```

Expected results:

- First request succeeds.
- Second request fails because no client certificate is presented.
- Third request reaches the backend with a valid CA-signed certificate, but fails with `401` because the CN is not authorized.

Internal validation toward robots:

```bash
docker compose exec ot-maintenance bash -lc '
curl -fsS \
  --cert "$CLIENT_TLS_CERT_FILE" \
  --key "$CLIENT_TLS_KEY_FILE" \
  https://robot-a-01:8443/update-firmware
'
```

Expected result includes:

```json
"authorized_client":"ot-maintenance"
```

## Step 19 - PKI Expiration, Rotation, and Revocation

Three simple mechanisms were added for operating the lab PKI without introducing a full CA manager.

### Phase A - Configurable Short Expiration

`scripts/generate-pki.sh` uses separate lifetimes:

```text
CA_DAYS=3650
SERVICE_DAYS=90
CLIENT_DAYS=30
```

Compose reads them from `.env`:

```text
PKI_CA_DAYS=3650
PKI_SERVICE_DAYS=90
PKI_CLIENT_DAYS=30
```

Changing these values does not automatically regenerate existing certificates. New values apply to newly generated or manually rotated certificates.

Validation:

```bash
openssl x509 -in data/pki/clients/ci-server/client.crt -noout -subject -enddate
openssl x509 -in data/pki/services/diagnostic-server/tls.crt -noout -subject -enddate
```

### Phase B - Manual Rotation

Script:

```text
scripts/rotate-pki-cert.sh
```

Host usage:

```bash
cd mecarobotix-lab
./scripts/rotate-pki-cert.sh client ci-server
./scripts/rotate-pki-cert.sh service diagnostic-server
```

Docker usage:

```bash
docker compose run --rm --entrypoint /usr/local/bin/rotate-pki-cert.sh pki-init client ci-server
docker compose run --rm --entrypoint /usr/local/bin/rotate-pki-cert.sh pki-init service diagnostic-server
```

Previous material is moved to:

```text
data/pki/rotated/clients/<CN>/<timestamp>/
data/pki/rotated/services/<service>/<timestamp>/
```

After rotation, recreate or restart services that use the certificate:

```bash
docker compose up -d --force-recreate diagnostic-server
docker compose up -d --force-recreate ci-server
```

If rotating ESP32 certificates, export the firmware header again before flashing:

```bash
ESP32_CLIENT_NAME=mrx-esp32-001 PKI_DIR=data/pki ./scripts/export-esp32-pki-material.sh
```

### Phase C - Simple Registry-Based Revocation

Revocation registry:

```text
data/pki/revoked-clients.txt
```

Format: one CN per line.

Scripts:

```bash
./scripts/revoke-pki-client.sh ci-server
./scripts/unrevoke-pki-client.sh ci-server
```

Docker equivalents:

```bash
docker compose run --rm --entrypoint /usr/local/bin/revoke-pki-client.sh pki-init ci-server
docker compose run --rm --entrypoint /usr/local/bin/unrevoke-pki-client.sh pki-init ci-server
```

`diagnostic-server` mounts the file at:

```text
/etc/mecarobotix/pki/revoked-clients.txt
```

`diagnostic-server` mTLS authorization flow:

1. `nginx` validates that the client certificate is signed by the CA.
2. The backend extracts the CN from `X-MTLS-Subject-DN`.
3. The CN must be safe for path usage.
4. `/etc/mecarobotix/pki/clients/<CN>/client.crt` must exist.
5. The CN must not appear in `revoked-clients.txt`.

Revocation validation:

```bash
./scripts/revoke-pki-client.sh ci-server
docker compose up -d --force-recreate diagnostic-server

curl --cacert data/pki/ca/ca.crt \
  --cert data/pki/clients/ci-server/client-chain.crt \
  --key data/pki/clients/ci-server/client.key \
  "https://localhost:8443/api/firmware/latest?robot_type=A"
```

Expected result: `401`.

Restore:

```bash
./scripts/unrevoke-pki-client.sh ci-server
docker compose up -d --force-recreate diagnostic-server
```

## Smoke Test Checklist

From `mecarobotix-lab`:

```bash
docker compose ps
```

Core HTTPS/mTLS checks:

```bash
curl --cacert data/pki/ca/ca.crt \
  --cert data/pki/clients/ci-server/client-chain.crt \
  --key data/pki/clients/ci-server/client.key \
  -i "https://localhost:8443/api/firmware/latest?robot_type=A"

curl --cacert data/pki/ca/ca.crt \
  -i "https://localhost:8443/api/firmware/latest?robot_type=A"

curl --cacert data/pki/ca/ca.crt \
  -i https://localhost:3000/api/healthz

curl --cacert data/pki/ca/ca.crt \
  -u jenkins_admin:Admin123! \
  -i https://localhost:8444/job/sync-gitea-release-to-artifact-registry/api/json
```

Robot mTLS:

```bash
docker compose exec ot-maintenance bash -lc '
curl -fsS \
  --cert "$CLIENT_TLS_CERT_FILE" \
  --key "$CLIENT_TLS_KEY_FILE" \
  https://robot-a-01:8443/status
'
```

Artifact registry:

```bash
docker compose exec ci-server bash -lc '
curl -fsS https://artifact-registry/firmware/robot-a-latest.bin -o /tmp/robot-a-latest.bin
ls -lh /tmp/robot-a-latest.bin
'
```

LDAPS:

```bash
docker compose exec ldap-server bash -lc '
LDAPTLS_CACERT=/etc/mecarobotix/pki/ca/ca.crt \
ldapwhoami -x -H ldaps://ldap-server:1636 \
  -D "cn=admin,dc=mecarobotix,dc=local" \
  -w "Admin123!"
'
```

PostgreSQL TLS:

```bash
docker compose exec db-internal bash -lc '
PGPASSWORD="Admin123!" psql \
"host=db-internal port=5432 dbname=mecarobotix user=admin_db sslmode=verify-full sslrootcert=/etc/mecarobotix/pki/ca/ca.crt" \
-c "select ssl from pg_stat_ssl where pid = pg_backend_pid();"
'
```

Quick expected result summary:

```text
diagnostic-server HTTPS + mTLS: 200 with cert, failure without cert
Gitea HTTPS: 200
Jenkins HTTPS: 200
Robot HTTPS + mTLS: 200 from ot-maintenance
Artifact registry HTTPS: firmware downloads
LDAPS: ldapwhoami succeeds
PostgreSQL TLS: ssl = t
Revocation: 200 -> 401 -> 200
```
