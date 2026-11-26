#!/bin/sh
set -eu

PKI_DIR="${PKI_DIR:-data/pki}"
CA_DIR="${PKI_DIR}/ca"
SERVICE_DIR="${PKI_DIR}/services"
CLIENT_DIR="${PKI_DIR}/clients"
CA_KEY="${CA_DIR}/ca.key"
CA_CERT="${CA_DIR}/ca.crt"
CA_SERIAL="${CA_DIR}/ca.srl"
CA_DAYS="${CA_DAYS:-3650}"
SERVICE_DAYS="${SERVICE_DAYS:-90}"
CLIENT_DAYS="${CLIENT_DAYS:-30}"
FORCE_PKI_REGENERATE="${FORCE_PKI_REGENERATE:-0}"
REVOCATION_FILE="${PKI_DIR}/revoked-clients.txt"

mkdir -p "$CA_DIR" "$SERVICE_DIR" "$CLIENT_DIR"
touch "$REVOCATION_FILE"
chmod 0644 "$REVOCATION_FILE"

need_openssl() {
  if ! command -v openssl >/dev/null 2>&1; then
    echo "[!] openssl is required to generate the lab PKI." >&2
    exit 1
  fi
}

write_ca_config() {
  cat > "${CA_DIR}/ca.cnf" <<'EOF'
[ req ]
prompt = no
distinguished_name = dn
x509_extensions = v3_ca

[ dn ]
C = FR
O = MecaRobotix Lab
OU = Internal PKI
CN = MecaRobotix Lab Root CA

[ v3_ca ]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints = critical,CA:true,pathlen:1
keyUsage = critical,keyCertSign,cRLSign
EOF
}

generate_ca() {
  write_ca_config

  if [ "$FORCE_PKI_REGENERATE" = "1" ]; then
    rm -f "$CA_KEY" "$CA_CERT" "$CA_SERIAL"
  fi

  if [ -f "$CA_KEY" ] && [ -f "$CA_CERT" ]; then
    echo "[=] Reusing existing lab CA: ${CA_CERT}"
    return
  fi

  echo "[+] Creating internal lab CA"
  openssl req \
    -x509 \
    -newkey rsa:4096 \
    -nodes \
    -sha256 \
    -days "$CA_DAYS" \
    -keyout "$CA_KEY" \
    -out "$CA_CERT" \
    -config "${CA_DIR}/ca.cnf"

  chmod 0600 "$CA_KEY"
  chmod 0644 "$CA_CERT"
}

write_service_config() {
  name="$1"
  dns_names="$2"
  ip_addresses="$3"
  cnf="$4"

  {
    cat <<EOF
[ req ]
prompt = no
distinguished_name = dn
req_extensions = v3_req

[ dn ]
C = FR
O = MecaRobotix Lab
OU = Internal Services
CN = ${name}

[ v3_req ]
subjectKeyIdentifier = hash
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature,keyEncipherment
extendedKeyUsage = serverAuth,clientAuth
subjectAltName = @alt_names

[ alt_names ]
EOF

    dns_index=1
    for dns_name in $dns_names; do
      printf 'DNS.%s = %s\n' "$dns_index" "$dns_name"
      dns_index=$((dns_index + 1))
    done

    ip_index=1
    for ip_address in $ip_addresses; do
      printf 'IP.%s = %s\n' "$ip_index" "$ip_address"
      ip_index=$((ip_index + 1))
    done
  } > "$cnf"
}

generate_service_cert() {
  name="$1"
  dns_names="$2"
  ip_addresses="$3"

  out_dir="${SERVICE_DIR}/${name}"
  key="${out_dir}/tls.key"
  csr="${out_dir}/tls.csr"
  crt="${out_dir}/tls.crt"
  chain="${out_dir}/tls-chain.crt"
  cnf="${out_dir}/san.cnf"

  mkdir -p "$out_dir"

  if [ "$FORCE_PKI_REGENERATE" = "1" ]; then
    rm -f "$key" "$csr" "$crt" "$chain" "$cnf"
  fi

  write_service_config "$name" "$dns_names" "$ip_addresses" "$cnf"

  if [ -f "$key" ] && [ -f "$crt" ]; then
    echo "[=] Reusing certificate for ${name}"
    return
  fi

  echo "[+] Creating certificate for ${name}"
  openssl req \
    -new \
    -newkey rsa:2048 \
    -nodes \
    -sha256 \
    -keyout "$key" \
    -out "$csr" \
    -config "$cnf"

  openssl x509 \
    -req \
    -in "$csr" \
    -CA "$CA_CERT" \
    -CAkey "$CA_KEY" \
    -CAcreateserial \
    -out "$crt" \
    -days "$SERVICE_DAYS" \
    -sha256 \
    -extensions v3_req \
    -extfile "$cnf"

  cat "$crt" "$CA_CERT" > "$chain"
  chmod 0600 "$key"
  chmod 0644 "$crt" "$chain" "$csr" "$cnf"
}

write_client_config() {
  name="$1"
  cnf="$2"

  cat > "$cnf" <<EOF
[ req ]
prompt = no
distinguished_name = dn
req_extensions = v3_req

[ dn ]
C = FR
O = MecaRobotix Lab
OU = Internal Clients
CN = ${name}

[ v3_req ]
subjectKeyIdentifier = hash
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature,keyEncipherment
extendedKeyUsage = clientAuth
EOF
}

generate_client_cert() {
  name="$1"

  out_dir="${CLIENT_DIR}/${name}"
  key="${out_dir}/client.key"
  csr="${out_dir}/client.csr"
  crt="${out_dir}/client.crt"
  chain="${out_dir}/client-chain.crt"
  cnf="${out_dir}/client.cnf"

  mkdir -p "$out_dir"

  if [ "$FORCE_PKI_REGENERATE" = "1" ]; then
    rm -f "$key" "$csr" "$crt" "$chain" "$cnf"
  fi

  write_client_config "$name" "$cnf"

  if [ -f "$key" ] && [ -f "$crt" ]; then
    echo "[=] Reusing client certificate for ${name}"
    return
  fi

  echo "[+] Creating client certificate for ${name}"
  openssl req \
    -new \
    -newkey rsa:2048 \
    -nodes \
    -sha256 \
    -keyout "$key" \
    -out "$csr" \
    -config "$cnf"

  openssl x509 \
    -req \
    -in "$csr" \
    -CA "$CA_CERT" \
    -CAkey "$CA_KEY" \
    -CAcreateserial \
    -out "$crt" \
    -days "$CLIENT_DAYS" \
    -sha256 \
    -extensions v3_req \
    -extfile "$cnf"

  cat "$crt" "$CA_CERT" > "$chain"
  chmod 0600 "$key"
  chmod 0644 "$crt" "$chain" "$csr" "$cnf"
}

need_openssl
generate_ca

generate_service_cert "firewall-int" "firewall-int firewall-int.mecarobotix.local" "10.10.10.1 10.10.20.1 10.10.30.1 10.10.40.1 10.10.50.1 10.10.100.1"
generate_service_cert "firewall-ext" "firewall-ext firewall-ext.mecarobotix.local" "10.10.10.2 10.10.3.1"
generate_service_cert "diagnostic-server" "diagnostic-server diagnostic-server.mecarobotix.local diagnostic.mecarobotix.local localhost" "10.10.10.3 10.93.22.136 127.0.0.1"
generate_service_cert "ldap-server" "ldap-server ldap-server.mecarobotix.local ldap.mecarobotix.local" "10.10.20.3"
generate_service_cert "phpldapadmin" "phpldapadmin phpldapadmin.mecarobotix.local" "10.10.20.4"
generate_service_cert "dns-server" "dns-server dns-server.mecarobotix.local dns.mecarobotix.local" "10.10.20.2"
generate_service_cert "devops-server" "devops-server devops-server.mecarobotix.local git.mecarobotix.local localhost" "10.10.30.2 127.0.0.1"
generate_service_cert "ci-server" "ci-server ci-server.mecarobotix.local jenkins.mecarobotix.local localhost" "10.10.30.4 127.0.0.1"
generate_service_cert "artifact-registry" "artifact-registry artifact-registry.mecarobotix.local artifacts.mecarobotix.local" "10.10.30.3"
generate_service_cert "it-services" "it-services it-services.mecarobotix.local files.mecarobotix.local" "10.10.40.2"
generate_service_cert "db-internal" "db-internal db-internal.mecarobotix.local db.mecarobotix.local" "10.10.40.3"
generate_service_cert "backup-log-server" "backup-log-server backup-log-server.mecarobotix.local backups.mecarobotix.local" "10.10.40.4"
generate_service_cert "ot-supervision" "ot-supervision ot-supervision.mecarobotix.local" "10.10.50.2"
generate_service_cert "ot-maintenance" "ot-maintenance ot-maintenance.mecarobotix.local" "10.10.50.3"
generate_service_cert "robot-a-01" "robot-a-01 robot-a-01.mecarobotix.local" "10.10.50.101"
generate_service_cert "robot-a-02" "robot-a-02 robot-a-02.mecarobotix.local" "10.10.50.102"
generate_service_cert "robot-b-01" "robot-b-01 robot-b-01.mecarobotix.local" "10.10.50.103"
generate_service_cert "client-robot-01" "client-robot-01 client-robot-01.mecarobotix.local" "10.10.3.10"
generate_service_cert "client-robot-02" "client-robot-02 client-robot-02.mecarobotix.local" "10.10.3.11"
generate_service_cert "mrx-esp32-001" "mrx-esp32-001 mrx-esp32-001.mecarobotix.local" ""
generate_service_cert "hacking-intranet-server" "hacking-intranet-server hacking-intranet-server.mecarobotix.local" "10.10.100.1"

generate_client_cert "robot-a-01"
generate_client_cert "robot-a-02"
generate_client_cert "robot-b-01"
generate_client_cert "client-robot-01"
generate_client_cert "client-robot-02"
generate_client_cert "mrx-esp32-001"
generate_client_cert "ot-maintenance"
generate_client_cert "ot-supervision"
generate_client_cert "ci-server"

echo "[+] PKI material is ready in ${PKI_DIR}"
echo "[+] Public CA certificate: ${CA_CERT}"
