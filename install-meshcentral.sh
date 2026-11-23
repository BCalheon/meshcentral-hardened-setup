#!/usr/bin/env bash
# Installs MeshCentral as a hardened systemd service on Ubuntu 24.04 LTS.
#
# Production (public VM with DNS already pointing at it):
#   sudo ./install-meshcentral.sh --domain mesh.example.com --email it@example.com
# Local rehearsal (self-signed cert for mesh.localtest.me, no firewall/SSH changes):
#   sudo ./install-meshcentral.sh --local
#
# Idempotent: safe to run again; it keeps an existing config.json and admin account.
set -euo pipefail

DOMAIN=""
EMAIL=""
ADMIN_USER="admin"
LOCAL=0
NODE_MAJOR=22
INSTALL_DIR="/opt/meshcentral"
DATA_DIR="$INSTALL_DIR/meshcentral-data"
SVC_USER="meshcentral"

usage() { sed -n '2,9p' "$0"; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --domain) DOMAIN="$2"; shift 2 ;;
    --email)  EMAIL="$2"; shift 2 ;;
    --admin)  ADMIN_USER="$2"; shift 2 ;;
    --local)  LOCAL=1; shift ;;
    *) usage ;;
  esac
done

[[ $EUID -eq 0 ]] || { echo "Run as root (sudo)."; exit 1; }
if [[ $LOCAL -eq 1 ]]; then
  # The hostname must contain a dot, or MeshCentral forces LAN-only mode.
  # *.localtest.me resolves to 127.0.0.1, so it reaches the WSL/VM through localhost forwarding.
  DOMAIN="${DOMAIN:-mesh.localtest.me}"
elif [[ -z "$DOMAIN" || -z "$EMAIL" ]]; then
  echo "Production mode needs --domain and --email (or use --local)."; exit 1
fi

log() { echo -e "\n==> $*"; }

log "Base packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get install -y -q ca-certificates curl gnupg openssl

log "Node.js ${NODE_MAJOR}.x LTS (NodeSource signed repo)"
if ! node -v 2>/dev/null | grep -q "^v${NODE_MAJOR}\."; then
  install -d -m 0755 /etc/apt/keyrings
  curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
    | gpg --dearmor --yes -o /etc/apt/keyrings/nodesource.gpg
  echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_MAJOR}.x nodistro main" \
    > /etc/apt/sources.list.d/nodesource.list
  apt-get update -q
  apt-get install -y -q nodejs
fi
node -v

log "Service user and MeshCentral package"
id "$SVC_USER" &>/dev/null || useradd --system --home-dir "$INSTALL_DIR" --shell /usr/sbin/nologin "$SVC_USER"
install -d -o "$SVC_USER" -g "$SVC_USER" -m 0750 "$INSTALL_DIR" "$DATA_DIR"
if [[ ! -d "$INSTALL_DIR/node_modules/meshcentral" ]]; then
  sudo -u "$SVC_USER" -H bash -c "cd '$INSTALL_DIR' && npm install --no-audit --no-fund meshcentral"
fi
MC_VERSION=$(node -p "require('$INSTALL_DIR/node_modules/meshcentral/package.json').version")
echo "MeshCentral $MC_VERSION"

log "config.json"
if [[ ! -f "$DATA_DIR/config.json" ]]; then
  if [[ $LOCAL -eq 1 ]]; then
    LE_BLOCK=''
  else
    LE_BLOCK=$(cat <<EOF
,
  "letsencrypt": {
    "email": "$EMAIL",
    "names": "$DOMAIN",
    "production": true
  }
EOF
)
  fi
  cat > "$DATA_DIR/config.json" <<EOF
{
  "\$schema": "https://raw.githubusercontent.com/Ylianst/MeshCentral/master/meshcentral-config-schema.json",
  "settings": {
    "cert": "$DOMAIN",
    "port": 443,
    "redirPort": 80,
    "mpsPort": 0,
    "WANonly": true,
    "selfUpdate": false,
    "allowFraming": false,
    "allowLoginToken": false,
    "cookieIpCheck": true,
    "maxInvalidLogin": { "time": 10, "count": 5, "coolofftime": 30 },
    "autoBackup": { "backupIntervalHours": 24, "keepLastDaysBackup": 14 }
  },
  "domains": {
    "": {
      "title": "Remote Management",
      "newAccounts": false,
      "passwordRequirements": {
        "min": 12, "upper": 1, "lower": 1, "numeric": 1, "nonalpha": 1,
        "force2factor": true
      }
    }
  }$LE_BLOCK
}
EOF
  chown "$SVC_USER:$SVC_USER" "$DATA_DIR/config.json"
  chmod 0640 "$DATA_DIR/config.json"
else
  echo "Existing config.json kept."
fi

log "systemd service"
cat > /etc/systemd/system/meshcentral.service <<EOF
[Unit]
Description=MeshCentral Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$SVC_USER
Group=$SVC_USER
WorkingDirectory=$INSTALL_DIR
ExecStart=/usr/bin/node $INSTALL_DIR/node_modules/meshcentral
Restart=always
RestartSec=10
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ProtectSystem=full
ProtectHome=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable meshcentral >/dev/null

log "Admin account"
CRED_FILE="/root/meshcentral-admin.txt"
if [[ ! -f "$CRED_FILE" ]]; then
  systemctl stop meshcentral || true
  ADMIN_PASS="$(openssl rand -base64 24 | tr -d '/+=' | cut -c1-20)Aa1!"
  ADMIN_EMAIL="${EMAIL:-admin@localhost.local}"
  MC="sudo -u $SVC_USER -H node $INSTALL_DIR/node_modules/meshcentral"
  (cd "$INSTALL_DIR" && $MC --createaccount "$ADMIN_USER" --pass "$ADMIN_PASS" --email "$ADMIN_EMAIL")
  (cd "$INSTALL_DIR" && $MC --adminaccount "$ADMIN_USER")
  umask 077
  printf 'URL: https://%s\nUser: %s\nPassword: %s\n' "$DOMAIN" "$ADMIN_USER" "$ADMIN_PASS" > "$CRED_FILE"
else
  echo "Admin already created (see $CRED_FILE)."
fi

systemctl restart meshcentral

if [[ $LOCAL -eq 0 ]]; then
  log "Firewall (ufw): SSH, 80, 443 only"
  apt-get install -y -q ufw fail2ban unattended-upgrades
  ufw default deny incoming
  ufw default allow outgoing
  ufw allow OpenSSH
  ufw allow 80/tcp
  ufw allow 443/tcp
  ufw --force enable

  log "fail2ban (sshd jail) and automatic security updates"
  systemctl enable --now fail2ban
  cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF

  log "SSH: key-only login"
  if compgen -G "/home/*/.ssh/authorized_keys" >/dev/null || [[ -s /root/.ssh/authorized_keys ]]; then
    cat > /etc/ssh/sshd_config.d/99-hardening.conf <<'EOF'
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin prohibit-password
EOF
    sshd -t && systemctl reload ssh
  else
    echo "WARNING: no authorized_keys found; password login left enabled to avoid lockout."
  fi
fi

log "Done"
echo "MeshCentral $MC_VERSION is running: https://$DOMAIN"
echo "Admin credentials: $CRED_FILE (store them in a password manager, then delete the file)."
echo "First login will require setting up 2FA (authenticator app)."
