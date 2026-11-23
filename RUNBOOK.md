# MeshCentral Server: Hand-off Runbook

Private MeshCentral server for secure, always-on remote management of Windows PCs.

| Item | Value |
|---|---|
| Console URL | `https://<DOMAIN>` |
| Server OS | Ubuntu 24.04 LTS |
| MeshCentral | `<VERSION>`, systemd service `meshcentral` |
| Install dir | `/opt/meshcentral` (owned by system user `meshcentral`) |
| Data / config | `/opt/meshcentral/meshcentral-data/config.json` |
| Backups | `/opt/meshcentral/meshcentral-backups` (automatic, daily, 14 days kept) |
| Open ports | 22 (SSH, key-only), 80 (redirect + Let's Encrypt renewal), 443 (console + agents) |

---

## 1. Security baseline (what was configured)

- **TLS:** Let's Encrypt certificate for `<DOMAIN>`, renewed automatically by MeshCentral. HTTP redirects to HTTPS.
- **No self-registration** (`newAccounts: false`). Only admins create accounts.
- **2FA is mandatory** (`force2factor`). A user without 2FA can log in but **cannot use any feature**
  until they enable an authenticator app under *My Account → Account Security*.
- **Password policy:** minimum 12 characters, with upper, lower, number and symbol.
- **Brute-force protection:** 5 failed logins in 10 minutes blocks the source IP for 30 minutes.
- **Hardened service:** runs as an unprivileged user; it only gets the capability to bind ports 80/443.
- **Unused Intel AMT port (4433) disabled** (`mpsPort: 0`).
- **OS:** firewall (ufw) allows only 22/80/443, fail2ban protects SSH, automatic security updates, SSH key-only login.

## 2. Daily use

1. Open `https://<DOMAIN>`, log in, and enter the 6-digit code from your authenticator app.
2. **My Devices** shows the device groups (**Desktops**, **Laptops**). Click a device to open:
   - **Desktop:** remote control.
   - **Terminal:** command prompt / PowerShell as SYSTEM.
   - **Files:** upload and download.

## 3. Adding administrators

1. **My Users → New Account**: set username, e-mail and a temporary password, and tick
   "Require password change on next login".
2. To make them a full admin: open the user → **Server Permissions** → grant the rights needed
   (full administrator only if really required).
3. To limit them to some PCs: open the **device group** → **Add Users** → pick the rights.
4. On first login they must set up 2FA before doing anything else.

## 4. Adding more PCs (scaling)

**Manual, one PC at a time:**
Device group → **Add Agent** → Windows → download the `.exe` → run as Administrator → **Install**.
The installer is bound to that group, so the PC lands in the right place.

**At scale (Intune or GPO):**
The Windows installer downloaded from **Add Agent** already carries this server's address and the
target group, so the same file can be pushed to many PCs. Silent install:
`MeshAgent.exe -fullinstall` (uninstall: `MeshAgent.exe -fulluninstall`).
1. Download **one installer per device group** (one for Laptops, one for Desktops).
2. Intune: package it as a *Win32 app* (`.intunewin`) with the install and uninstall commands
   above, and assign it to the matching Entra device group.
   GPO: a computer *startup script* that runs the same command from a network share.
3. Pilot on 1–2 PCs first, then roll out to the rest.

If SmartScreen warns about the installer, choose *More info → Run anyway*. The agent is signed
with this server's own code-signing certificate.

**Removing a PC:** open the device → **Actions → Uninstall Agent / Delete Device**.
Or on the PC: *Apps → Mesh Agent → Uninstall*.

## 5. Backups and restore

- MeshCentral writes a backup zip every 24 h to `/opt/meshcentral/meshcentral-backups` and keeps 14 days.
- **Recommended:** copy those zips off-server too (e.g. provider snapshots, or a nightly sync to S3/B2).
  A backup that lives only on the same VM does not survive losing the VM.

**Restore on a new server:**
1. Run `install-meshcentral.sh` with the same `--domain` and `--email`.
2. `sudo systemctl stop meshcentral`
3. Unzip the backup into `/opt/meshcentral/meshcentral-data` (replace the files), then
   `sudo chown -R meshcentral:meshcentral /opt/meshcentral`.
4. `sudo systemctl start meshcentral`, then point DNS to the new IP. Agents reconnect on their own
   because the server certificates were restored with the data.

## 6. Updates

```bash
# OS security updates are automatic. Full OS upgrade (monthly):
sudo apt update && sudo apt full-upgrade -y && sudo reboot

# MeshCentral update (self-update is disabled on purpose, so updates are deliberate):
sudo systemctl stop meshcentral
cd /opt/meshcentral && sudo -u meshcentral npm install meshcentral@latest
sudo systemctl start meshcentral
```
Take a provider snapshot before updating. To roll back, restore the snapshot, or reinstall the
previous version with `npm install meshcentral@<old-version>`.

## 7. Troubleshooting

| Symptom | Check |
|---|---|
| Console unreachable | `systemctl status meshcentral`; `journalctl -u meshcentral -n 50`; `sudo ufw status` |
| Certificate warning | DNS still points to the server? Port 80 open (Let's Encrypt renews through it)? |
| Agent offline | PC online? Outbound 443 to `<DOMAIN>` allowed by the PC's network or proxy? |
| Locked out (lost 2FA) | Another admin resets 2FA for the user under **My Users**. Keep at least 2 admin accounts. |
| Too many failed logins | Wait 30 minutes; the block is per IP address. |
