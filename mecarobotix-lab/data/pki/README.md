# MecaRobotix Lab PKI

This directory is populated by `scripts/generate-pki.sh` or the `pki-init`
Compose service.

Generated private keys and certificates are intentionally ignored by Git.

Expected layout after generation:

```text
data/pki/
  ca/
    ca.crt
    ca.key
  services/
    diagnostic-server/
      tls.crt
      tls.key
      tls-chain.crt
    ...
  clients/
    robot-a-01/
      client.crt
      client.key
      client-chain.crt
    ot-maintenance/
      client.crt
      client.key
      client-chain.crt
    ...
  revoked-clients.txt
  rotated/
    clients/
    services/
```

Do not commit generated private keys.

Certificate lifetimes are configurable through environment variables:

```bash
CA_DAYS=3650 SERVICE_DAYS=90 CLIENT_DAYS=30 scripts/generate-pki.sh
```

Manual rotation keeps the previous material under `data/pki/rotated/...` and
generates a replacement with the same configured identity:

```bash
scripts/rotate-pki-cert.sh client ci-server
scripts/rotate-pki-cert.sh service diagnostic-server
```

Client revocation is a simple CN registry. A revoked CN stays signed by the CA,
but services that consume `revoked-clients.txt` reject it during authorization:

```bash
scripts/revoke-pki-client.sh ci-server
scripts/unrevoke-pki-client.sh ci-server
```
