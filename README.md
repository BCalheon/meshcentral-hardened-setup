# MeshCentral Hardened Setup

One-command, production-ready [MeshCentral](https://github.com/Ylianst/MeshCentral) server on
Ubuntu 24.04: self-hosted remote management for Windows fleets (remote desktop, terminal, file
transfer) without TeamViewer/AnyDesk licenses, and with security defaults turned **on**.

```bash
sudo ./install-meshcentral.sh --domain mesh.example.com --email it@example.com
```

## What the installer does

| Area | Default |
|---|---|
| **TLS** | Let's Encrypt certificate for your domain, renewed automatically; HTTP → HTTPS redirect |
| **Accounts** | Self-registration disabled; admin created by CLI with a random password |
| **2FA** | Mandatory: users cannot use any feature until an authenticator app is set up |
| **Passwords** | 12+ chars with upper, lower, digit and symbol |
| **Brute force** | 5 failed logins in 10 min → source IP blocked for 30 min |
| **Service** | systemd, unprivileged `meshcentral` user, only `CAP_NET_BIND_SERVICE`, `ProtectSystem=full` |
| **Attack surface** | Intel AMT MPS port 4433 disabled, WAN-only mode, framing and login tokens disabled |
| **OS** | ufw (22/80/443 only), fail2ban, unattended security upgrades, SSH key-only (applied only if a key exists, to avoid lockout) |
| **Backups** | Built-in daily backup, 14 days retained |
| **Updates** | Self-update off: upgrades are deliberate and snapshot-backed (see runbook) |

The script is **idempotent**: re-running it keeps the existing config and admin account.

## Rehearse locally first

Test the whole flow on your machine (WSL2 or a local VM) before touching a client server:

```bash
sudo ./install-meshcentral.sh --local
```

`--local` uses a self-signed certificate for `mesh.localtest.me`, which resolves to `127.0.0.1`,
and skips firewall and SSH changes. A dotted hostname matters: with a bare name like
`localhost`, MeshCentral silently forces **LAN-only mode** and remote agents cannot connect.

Validate the config keys against the official schema:

```bash
curl -fsSL -o schema.json https://raw.githubusercontent.com/Ylianst/MeshCentral/master/meshcentral-config-schema.json
node tools/check-config.js /opt/meshcentral schema.json
```

## Hand-off

[`RUNBOOK.md`](./RUNBOOK.md) is the client-facing guide: daily use, adding admins, rolling the
agent out with Intune/GPO, backup and restore, updates, and troubleshooting.

## Tested with

Ubuntu 24.04 LTS, Node.js 22 LTS, MeshCentral 1.3.1, Windows 11 agent: remote desktop, terminal
and file transfer validated end to end.
