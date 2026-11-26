# MécaRobotix Vulnerable Lab Architecture

```text
                         [External Robots / Client Sites]
                                      |
                               client_robot_net
                                10.10.3.0/24
                                      |
                                      v
                              [firewall-router]
                         /            |             \
                        /             |              \
              updates_net      internal_flat_net    client_robot_net
             10.10.2.0/24       10.10.1.0/24        10.10.3.0/24
                    |                  |                    |
          diagnostic-server      internal services     client robots
```

The Docker implementation uses a simplified model:

- `diagnostic-server` is multi-homed on `updates_net` and `internal_flat_net`.
- This simulates an overly permissive DMZ-to-internal communication path.
- `client_robot_net` is not routed from `internal_flat_net`.
- No management network is included in this version.

## Functional blocks

| Block | Hosts |
|---|---|
| DMZ / Updates | `diagnostic-server` |
| Identity / DNS | `ldap-server`, `phpldapadmin`, `dns-server` |
| DevOps / CI | `devops-server`, `artifact-registry`, `ci-server` |
| IT / Data | `it-services`, `db-internal`, `backup-log-server` |
| OT | `ot-supervision`, `ot-maintenance`, `robot-a-01`, `robot-a-02`, `robot-b-01` |
| Testing | `hacking-intranet-server` |
| Client side | `client-robot-01`, `client-robot-02` |
