List of changes implementing a local CA:

Inventory all current HTTP communications.
Create an internal lab CA.
Generate TLS certificates for each service.
Include the correct SANs in each certificate.
Distribute the public CA to all client containers.
Enable HTTPS on the diagnostic-server.
Configure robots to use HTTPS when communicating with the diagnostic-server.
Enable HTTPS on the robots' APIs.
Configure ot-maintenance to use HTTPS.
Configure ot-supervision to use HTTPS.
Enable HTTPS on the artifact-registry.
Switch firmware URLs to HTTPS.
Configure the diagnostic-server to return HTTPS URLs.
Configure Jenkins / ci-server to use HTTPS.
Enable HTTPS on Gitea / devops-server.
Update Gitea webhooks to Jenkins via HTTPS.
Enable HTTPS on Jenkins / ci-server.
Switch from LDAP to LDAPS.
Enable TLS on PostgreSQL.
Remove secrets sent via query strings.
Move tokens/secrets to headers or more secure mechanisms.
Generate client certificates for robots.
Generate client certificates for ot-maintenance.
Generate client certificates for ot-supervision.
Generate client certificates for ci-server.
Enable mTLS on robots -> diagnostic-server.
Enable mTLS on ot-maintenance -> robots.
Enable mTLS on ot-supervision -> robots.
Enable mTLS on ci-server -> critical services.
Reduce or eliminate hardcoded tokens.
Add short certificate expiration.
Implement certificate rotation.
Implement certificate revocation.
