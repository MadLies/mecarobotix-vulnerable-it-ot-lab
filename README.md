# Mécarobotix Project

**Students:** Fadi Beirouty, Juan Wilches Correa, Otávio de Oliveira Silva, Rafael Kaiki Sesoko

Information about the maquette infrastructure up to date can be found on the file `InfraMaquette.txt`.

Designs to aid understanding can be found in the `excalidraw/` folder. Upload them to the [Excalidraw website](https://excalidraw.com/) for visualization.

## How to execute

First, build the project:

```bash
cd mecarobotix-lab
docker compose build --no-cache
```

To run it:

```bash
docker compose up -d
```

To check the current status:

```bash
docker compose ps -a --format 'table {{.Name}}\t{{.Status}}\t{{.State}}\t{{.Ports}}'
```

To turn it down:

```bash
docker compose down -v --remove-orphans
```

---

## ⚠️ Disclaimer
This is an **intentionally vulnerable** lab for education. All credentials, tokens and "sensitive" files in it (`.env`, LDAP bootstrap, `*_SIMULATION.*`) are fake and were created for the exercise. Do not deploy it on a network you do not control. WiFi credentials in the firmware were replaced with placeholders (`Firmware/include/config.h`).

## Authors
Group project for the 4CS08 course (Télécom Paris, 2026) by **Fadi Beirouty, Juan David Wilches Correa, Otávio de Oliveira Silva and Rafael Kaiki Sesoko**.

My main contributions: base infrastructure and the vulnerable C web server, the vulnerable ESP32 firmware and its embedded server, the HTTP plaintext-token scenario, the DNS zone transfer attack, the vulnerable services (file share/FTP/SMB, database, Gitea, Jenkins CI with job-to-shell, OT maintenance and supervision with cleartext secrets and root cronjobs, shared root SSH account), and the remediation work (internal PKI and token-less authentication, network segmentation).
