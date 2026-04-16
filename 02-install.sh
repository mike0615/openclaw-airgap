#!/usr/bin/env bash
# =============================================================================
# OpenClaw Air-Gap Installer
# =============================================================================
# Run this on the AIR-GAPPED Rocky Linux 9 target machine.
#
# Usage:
#   sudo bash install.sh [--user mike] [--workspace /opt/openclaw] [--hostname ai.local]
#
# Defaults:
#   --user       openclaw   (dedicated system user; use your login name to run as yourself)
#   --workspace  /opt/openclaw/workspace
#   --hostname   localhost  (hostname/IP clients will use to reach Mattermost)
#
# What this installs:
#   1. Node.js 22 + pnpm
#   2. OpenClaw (gateway + CLI)
#   3. Ollama + LLM model
#   4. PostgreSQL 16 (for Mattermost)
#   5. Mattermost (self-hosted chat – replaces Discord/Telegram)
#   6. n8n (workflow automation – replaces Zapier)
#   7. faster-whisper (voice transcription)
#   8. OpenClaw Mission Control dashboard
#   9. All systemd services + firewall rules
#  10. Workspace, identity files, heartbeat config
# =============================================================================

set -euo pipefail

# ── Parse arguments ───────────────────────────────────────────────────────────
AGENT_USER="openclaw"
OC_WORKSPACE="/opt/openclaw/workspace"
SERVER_HOSTNAME="localhost"
BUNDLE_DIR="$(cd "$(dirname "$0")" && pwd)"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --user)      AGENT_USER="$2";     shift 2 ;;
    --workspace) OC_WORKSPACE="$2";   shift 2 ;;
    --hostname)  SERVER_HOSTNAME="$2";shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

# ── Helpers ───────────────────────────────────────────────────────────────────
log()  { echo -e "\033[1;32m[+]\033[0m $*"; }
info() { echo -e "\033[1;34m[i]\033[0m $*"; }
warn() { echo -e "\033[1;33m[!]\033[0m $*"; }
die()  { echo -e "\033[1;31m[✗]\033[0m $*" >&2; exit 1; }
step() { echo ""; echo -e "\033[1;36m━━━ Step $1: $2 ━━━\033[0m"; }

OC_HOME="/opt/openclaw"
OC_CONFIG="$OC_HOME/.openclaw"
OLLAMA_HOME="/opt/ollama"
MM_HOME="/opt/mattermost"
N8N_HOME="/opt/n8n"
MC_HOME="/opt/mission-control"
PG_DATA="/var/lib/pgsql/16/data"

# ── Preflight ─────────────────────────────────────────────────────────────────
[[ "$(id -u)" -eq 0 ]] || die "Run as root or with sudo."
[[ -f "$BUNDLE_DIR/MANIFEST.txt" ]] || die "Must run from inside the bundle directory."

echo ""
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║           OpenClaw Air-Gap Installer                         ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
cat "$BUNDLE_DIR/MANIFEST.txt"
echo ""
log "Agent user:  $AGENT_USER"
log "Workspace:   $OC_WORKSPACE"
log "Server host: $SERVER_HOSTNAME"
echo ""
read -rp "Proceed with installation? [y/N] " CONFIRM
[[ "${CONFIRM,,}" == "y" ]] || { echo "Aborted."; exit 0; }

# Grab model name from manifest
MODEL=$(grep "^Model:" "$BUNDLE_DIR/MANIFEST.txt" | awk '{print $2}' || echo "qwen2.5:14b")

# ─────────────────────────────────────────────────────────────────────────────
step 1 "RPM packages"
# ─────────────────────────────────────────────────────────────────────────────

# Add local repo
cat > /etc/yum.repos.d/openclaw-local.repo << EOF
[openclaw-local]
name=OpenClaw Local Bundle
baseurl=file://${BUNDLE_DIR}/rpms
enabled=1
gpgcheck=0
EOF

dnf install -y --disablerepo="*" --enablerepo="openclaw-local" \
  nodejs git gcc gcc-c++ make \
  python3 python3-pip python3-devel \
  postgresql16-server postgresql16 \
  redis \
  firewalld \
  jq openssl 2>/dev/null || \
dnf install -y \
  nodejs git gcc gcc-c++ make \
  python3 python3-pip python3-devel \
  postgresql16-server postgresql16 \
  redis firewalld jq openssl || \
  warn "Some RPMs failed – install manually from $BUNDLE_DIR/rpms/"

# ffmpeg (may be in separate EPEL repo in bundle)
dnf install -y --disablerepo="*" --enablerepo="openclaw-local" ffmpeg 2>/dev/null || \
  warn "ffmpeg not installed – voice transcription will still work without it"

# Verify Node.js
node --version >/dev/null 2>&1 || die "Node.js installation failed."
log "Node.js: $(node --version)"

# ─────────────────────────────────────────────────────────────────────────────
step 2 "pnpm"
# ─────────────────────────────────────────────────────────────────────────────

if [[ -f "$BUNDLE_DIR/binaries/pnpm" ]]; then
  install -m 755 "$BUNDLE_DIR/binaries/pnpm" /usr/local/bin/pnpm
else
  npm install -g pnpm || warn "pnpm install failed – using npm fallback"
fi
log "pnpm: $(pnpm --version 2>/dev/null || echo 'not installed, using npm')"

# ─────────────────────────────────────────────────────────────────────────────
step 3 "System users and directories"
# ─────────────────────────────────────────────────────────────────────────────

# Create agent user if it doesn't exist and isn't a system login
if ! id "$AGENT_USER" &>/dev/null; then
  useradd -r -m -d "$OC_HOME" -s /bin/bash "$AGENT_USER"
  log "Created user: $AGENT_USER"
fi

# Ollama user
id ollama &>/dev/null || useradd -r -m -d "$OLLAMA_HOME" -s /bin/false ollama

# Mattermost user
id mattermost &>/dev/null || useradd -r -m -d "$MM_HOME" -s /bin/false mattermost

mkdir -p \
  "$OC_HOME" "$OC_CONFIG" "$OC_WORKSPACE" \
  "$OC_WORKSPACE/skills" \
  "$OC_WORKSPACE/memory" \
  "$OLLAMA_HOME" \
  "$MM_HOME" \
  "$N8N_HOME" \
  "$MC_HOME" \
  /var/log/openclaw

chown -R "$AGENT_USER:$AGENT_USER" "$OC_HOME" /var/log/openclaw
chown -R ollama:ollama "$OLLAMA_HOME"
chown -R mattermost:mattermost "$MM_HOME"

# ─────────────────────────────────────────────────────────────────────────────
step 4 "OpenClaw"
# ─────────────────────────────────────────────────────────────────────────────

OC_MODULES="/opt/openclaw-modules"
mkdir -p "$OC_MODULES"

log "Extracting OpenClaw node_modules..."
tar xzf "$BUNDLE_DIR/node-packages/openclaw-node_modules.tar.gz" -C "$OC_MODULES"

# Create wrapper for openclaw CLI
cat > /usr/local/bin/openclaw << 'WRAPPER'
#!/bin/bash
exec node /opt/openclaw-modules/node_modules/.bin/openclaw "$@"
WRAPPER
chmod +x /usr/local/bin/openclaw

# Verify
openclaw --version 2>/dev/null && log "OpenClaw installed: $(openclaw --version 2>/dev/null)" \
  || warn "openclaw CLI may need the gateway running – continuing..."

# Write OpenClaw main config
install -m 644 -o "$AGENT_USER" -g "$AGENT_USER" \
  "$BUNDLE_DIR/configs/openclaw.json" \
  "$OC_CONFIG/openclaw.json"

# Substitute hostname in config
sed -i "s|__SERVER_HOSTNAME__|${SERVER_HOSTNAME}|g" "$OC_CONFIG/openclaw.json"
sed -i "s|__WORKSPACE__|${OC_WORKSPACE}|g"         "$OC_CONFIG/openclaw.json"
sed -i "s|__MODEL__|${MODEL}|g"                    "$OC_CONFIG/openclaw.json"

# Copy identity files
cp -n "$BUNDLE_DIR/configs/identity/"*.md "$OC_WORKSPACE/" 2>/dev/null || true
chown -R "$AGENT_USER:$AGENT_USER" "$OC_WORKSPACE"

log "OpenClaw config: $OC_CONFIG/openclaw.json"

# ─────────────────────────────────────────────────────────────────────────────
step 5 "Ollama"
# ─────────────────────────────────────────────────────────────────────────────

log "Installing Ollama binary..."
if [[ -f "$BUNDLE_DIR/binaries/ollama-linux-amd64.tgz" ]]; then
  tar xzf "$BUNDLE_DIR/binaries/ollama-linux-amd64.tgz" -C /tmp/
  find /tmp -name "ollama" -type f -exec install -m 755 {} /usr/local/bin/ollama \; 2>/dev/null | head -1
  rm -rf /tmp/bin 2>/dev/null || true
elif [[ -f "$BUNDLE_DIR/binaries/ollama" ]]; then
  install -m 755 "$BUNDLE_DIR/binaries/ollama" /usr/local/bin/ollama
else
  die "Ollama binary not found in bundle. Re-run 01-prepare-bundle.sh."
fi
log "Ollama: $(ollama --version 2>/dev/null || echo 'installed')"

# Restore models
log "Restoring Ollama models (may take several minutes)..."
if [[ -f "$BUNDLE_DIR/models/ollama-models.tar.gz" ]]; then
  tar xzf "$BUNDLE_DIR/models/ollama-models.tar.gz" -C "$OLLAMA_HOME/"
  chown -R ollama:ollama "$OLLAMA_HOME"
  log "  Model restored: $MODEL"
else
  warn "No model archive found. You must manually pull a model after connecting to internet,"
  warn "or copy ~/.ollama/models/ from another machine."
fi

# ─────────────────────────────────────────────────────────────────────────────
step 6 "PostgreSQL (for Mattermost)"
# ─────────────────────────────────────────────────────────────────────────────

if ! postgresql16-setup initdb 2>/dev/null; then
  warn "PostgreSQL init skipped (may already be initialized)"
fi

systemctl enable postgresql-16
systemctl start postgresql-16
sleep 2

# Create Mattermost database and user
MM_DB_PASS=$(openssl rand -base64 24 | tr -d '/+=')
sudo -u postgres psql -c "CREATE USER mmuser WITH PASSWORD '${MM_DB_PASS}';" 2>/dev/null || \
  warn "mmuser may already exist"
sudo -u postgres psql -c "CREATE DATABASE mattermost OWNER mmuser;" 2>/dev/null || \
  warn "mattermost database may already exist"

# Save credentials
cat > /root/.mattermost-db-creds << EOF
DB_USER=mmuser
DB_PASS=${MM_DB_PASS}
DB_NAME=mattermost
EOF
chmod 600 /root/.mattermost-db-creds
log "PostgreSQL credentials saved to /root/.mattermost-db-creds"

# ─────────────────────────────────────────────────────────────────────────────
step 7 "Mattermost"
# ─────────────────────────────────────────────────────────────────────────────

MM_ARCHIVE=$(ls "$BUNDLE_DIR/mattermost/"*.tar.gz 2>/dev/null | head -1)
if [[ -z "$MM_ARCHIVE" ]]; then
  warn "Mattermost archive not found in bundle – skipping."
  warn "Download from https://mattermost.com/deploy/ and place in $BUNDLE_DIR/mattermost/"
else
  tar xzf "$MM_ARCHIVE" -C "$MM_HOME" --strip-components=1
  chown -R mattermost:mattermost "$MM_HOME"

  # Write Mattermost config
  MM_CONFIG="$MM_HOME/config/config.json"
  cat > "$MM_CONFIG" << MMCFG
{
  "ServiceSettings": {
    "SiteURL": "http://${SERVER_HOSTNAME}:8065",
    "ListenAddress": ":8065",
    "ConnectionSecurity": "",
    "EnableBotAccountCreation": true,
    "EnableAPIv3": false
  },
  "SqlSettings": {
    "DriverName": "postgres",
    "DataSource": "postgres://mmuser:${MM_DB_PASS}@localhost:5432/mattermost?sslmode=disable",
    "MaxIdleConns": 10,
    "MaxOpenConns": 100,
    "Trace": false
  },
  "TeamSettings": {
    "SiteName": "OpenClaw AI",
    "MaxUsersPerTeam": 50,
    "EnableTeamCreation": true,
    "EnableUserCreation": true
  },
  "EmailSettings": {
    "SendEmailNotifications": false,
    "EnableSignUpWithEmail": true,
    "RequireEmailVerification": false,
    "SMTPServer": "",
    "SMTPPort": ""
  },
  "FileSettings": {
    "MaxFileSize": 104857600
  },
  "LogSettings": {
    "EnableConsole": true,
    "ConsoleLevel": "INFO",
    "EnableFile": true,
    "FileLevel": "WARN",
    "FileLocation": "/var/log/openclaw/mattermost.log"
  }
}
MMCFG

  chown mattermost:mattermost "$MM_CONFIG"
  log "Mattermost configured."
fi

# ─────────────────────────────────────────────────────────────────────────────
step 8 "n8n (workflow automation)"
# ─────────────────────────────────────────────────────────────────────────────

N8N_MODULES="/opt/n8n-modules"
mkdir -p "$N8N_MODULES"

if [[ -f "$BUNDLE_DIR/node-packages/n8n-node_modules.tar.gz" ]]; then
  tar xzf "$BUNDLE_DIR/node-packages/n8n-node_modules.tar.gz" -C "$N8N_MODULES"

  cat > /usr/local/bin/n8n << 'WRAPPER'
#!/bin/bash
exec node /opt/n8n-modules/node_modules/.bin/n8n "$@"
WRAPPER
  chmod +x /usr/local/bin/n8n
  log "n8n installed."
else
  warn "n8n archive not found – skipping."
fi

# ─────────────────────────────────────────────────────────────────────────────
step 9 "faster-whisper (voice transcription)"
# ─────────────────────────────────────────────────────────────────────────────

if [[ -d "$BUNDLE_DIR/python-wheels" ]] && ls "$BUNDLE_DIR/python-wheels/"*.whl &>/dev/null; then
  pip3 install --no-index --find-links="$BUNDLE_DIR/python-wheels/" \
    faster-whisper numpy 2>/dev/null || \
  pip3 install --find-links="$BUNDLE_DIR/python-wheels/" \
    faster-whisper 2>/dev/null || \
    warn "faster-whisper install failed – voice features disabled"
else
  warn "Python wheels not found – voice transcription disabled."
fi

# Copy Whisper model
if [[ -d "$BUNDLE_DIR/models/whisper" ]]; then
  mkdir -p /opt/openclaw/whisper-models
  cp -r "$BUNDLE_DIR/models/whisper/"* /opt/openclaw/whisper-models/ 2>/dev/null || true
  chown -R "$AGENT_USER:$AGENT_USER" /opt/openclaw/whisper-models
fi

# Create whisper transcription helper script
cat > /usr/local/bin/openclaw-transcribe << 'TRANSCRIBE'
#!/usr/bin/env python3
"""Voice memo transcription helper for OpenClaw."""
import sys
from faster_whisper import WhisperModel

audio_file = sys.argv[1] if len(sys.argv) > 1 else sys.stdin.buffer.read()
model = WhisperModel("base.en", device="cpu",
                     download_root="/opt/openclaw/whisper-models")
segments, _ = model.transcribe(audio_file)
print(" ".join(s.text for s in segments).strip())
TRANSCRIBE
chmod +x /usr/local/bin/openclaw-transcribe

# ─────────────────────────────────────────────────────────────────────────────
step 10 "Mission Control dashboard"
# ─────────────────────────────────────────────────────────────────────────────

if [[ -f "$BUNDLE_DIR/node-packages/openclaw-mission-control-built.tar.gz" ]]; then
  tar xzf "$BUNDLE_DIR/node-packages/openclaw-mission-control-built.tar.gz" -C "$MC_HOME"
  chown -R "$AGENT_USER:$AGENT_USER" "$MC_HOME"

  cat > /usr/local/bin/openclaw-mc << MCWRAP
#!/bin/bash
cd $MC_HOME
exec node server.js --port 3001 2>/dev/null || \
  exec npx serve . --port 3001 2>/dev/null || \
  echo "Mission Control: open $MC_HOME/index.html in a browser"
MCWRAP
  chmod +x /usr/local/bin/openclaw-mc
  log "Mission Control installed at $MC_HOME"
else
  warn "Mission Control not installed – bundle may not have included it."
fi

# ─────────────────────────────────────────────────────────────────────────────
step 11 "systemd services"
# ─────────────────────────────────────────────────────────────────────────────

for svc in ollama openclaw mattermost n8n; do
  if [[ -f "$BUNDLE_DIR/configs/systemd/${svc}.service" ]]; then
    sed "s|__AGENT_USER__|${AGENT_USER}|g; \
         s|__OC_HOME__|${OC_HOME}|g; \
         s|__OC_CONFIG__|${OC_CONFIG}|g; \
         s|__OLLAMA_HOME__|${OLLAMA_HOME}|g; \
         s|__MM_HOME__|${MM_HOME}|g; \
         s|__N8N_HOME__|${N8N_HOME}|g" \
      "$BUNDLE_DIR/configs/systemd/${svc}.service" \
      > "/etc/systemd/system/${svc}.service"
    log "  Installed ${svc}.service"
  fi
done

systemctl daemon-reload

# Enable and start services in order
SERVICES_TO_START=(postgresql-16 ollama mattermost n8n openclaw)
for svc in "${SERVICES_TO_START[@]}"; do
  if systemctl list-unit-files | grep -q "^${svc}.service"; then
    systemctl enable "$svc" 2>/dev/null || true
    systemctl start  "$svc" 2>/dev/null && log "  Started: $svc" \
      || warn "  Failed to start $svc (check: journalctl -u $svc)"
    sleep 2
  fi
done

# ─────────────────────────────────────────────────────────────────────────────
step 12 "Firewall"
# ─────────────────────────────────────────────────────────────────────────────

systemctl enable firewalld
systemctl start  firewalld

# OpenClaw gateway
firewall-cmd --permanent --add-port=18789/tcp   # OpenClaw gateway
# Mattermost
firewall-cmd --permanent --add-port=8065/tcp    # Mattermost HTTP
# n8n
firewall-cmd --permanent --add-port=5678/tcp    # n8n
# Mission Control
firewall-cmd --permanent --add-port=3001/tcp    # Dashboard

firewall-cmd --reload
log "Firewall rules applied."

# ─────────────────────────────────────────────────────────────────────────────
step 13 "Post-install: Mattermost bot setup"
# ─────────────────────────────────────────────────────────────────────────────

info "Waiting for Mattermost to become ready..."
for i in {1..30}; do
  curl -sf "http://localhost:8065/api/v4/system/ping" >/dev/null 2>&1 && break
  sleep 3
done

if curl -sf "http://localhost:8065/api/v4/system/ping" >/dev/null 2>&1; then
  log "Mattermost is up."
  info "============================================================"
  info " REQUIRED MANUAL STEP: Create admin account + bot token"
  info "============================================================"
  info " 1. Open http://${SERVER_HOSTNAME}:8065 in a browser"
  info " 2. Create your admin account"
  info " 3. Create a team named: openclaw"
  info " 4. Go to: Main Menu → Integrations → Bot Accounts"
  info " 5. Click 'Add Bot Account'"
  info "    Username:    openclaw-agent"
  info "    Display Name: OpenClaw Agent"
  info "    Role:        System Admin"
  info " 6. Copy the bot TOKEN"
  info " 7. Run: sudo openclaw-configure-mattermost <TOKEN>"
  info "============================================================"
else
  warn "Mattermost not yet responding – configure manually after startup."
fi

# Create the configure-mattermost helper
cat > /usr/local/bin/openclaw-configure-mattermost << CFGHELPER
#!/usr/bin/env bash
# Usage: openclaw-configure-mattermost <BOT_TOKEN>
TOKEN="\$1"
[[ -z "\$TOKEN" ]] && { echo "Usage: \$0 <mattermost-bot-token>"; exit 1; }

OC_CONFIG="${OC_CONFIG}"
CFG="\$OC_CONFIG/openclaw.json"
[[ -f "\$CFG" ]] || { echo "Config not found: \$CFG"; exit 1; }

# Inject token into config using python3 (jq won't handle json5)
python3 << PYEOF
import json, sys
with open('\$CFG', 'r') as f:
    cfg = json.load(f)
cfg.setdefault('channels', {}).setdefault('mattermost', {})['botToken'] = '\$TOKEN'
cfg['channels']['mattermost']['enabled'] = True
with open('\$CFG', 'w') as f:
    json.dump(cfg, f, indent=2)
print("Mattermost bot token saved to \$CFG")
PYEOF

chown ${AGENT_USER}:${AGENT_USER} "\$CFG"
systemctl restart openclaw
echo "OpenClaw restarted. Check status: systemctl status openclaw"
CFGHELPER
chmod +x /usr/local/bin/openclaw-configure-mattermost

# ─────────────────────────────────────────────────────────────────────────────
step 14 "Identity files"
# ─────────────────────────────────────────────────────────────────────────────

info "Workspace identity files installed at $OC_WORKSPACE/"
info "Edit these files to personalize your agent:"
for f in SOUL.md AGENTS.md TOOLS.md user.md memory.md HEARTBEAT.md; do
  if [[ -f "$OC_WORKSPACE/$f" ]]; then
    echo "  → $OC_WORKSPACE/$f"
  fi
done
info "Then run: systemctl restart openclaw"

# ─────────────────────────────────────────────────────────────────────────────
step 15 "Health check"
# ─────────────────────────────────────────────────────────────────────────────

echo ""
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║                  Installation Summary                        ║"
echo "╚═══════════════════════════════════════════════════════════════╝"

check_svc() {
  local svc="$1"
  local label="$2"
  if systemctl is-active --quiet "$svc" 2>/dev/null; then
    echo -e "  \033[1;32m✓\033[0m $label"
  else
    echo -e "  \033[1;31m✗\033[0m $label (check: journalctl -u $svc -n 20)"
  fi
}

check_cmd() {
  local cmd="$1"
  local label="$2"
  if command -v "$cmd" >/dev/null 2>&1; then
    echo -e "  \033[1;32m✓\033[0m $label"
  else
    echo -e "  \033[1;33m~\033[0m $label (not in PATH)"
  fi
}

check_svc postgresql-16  "PostgreSQL 16"
check_svc ollama         "Ollama (LLM server)"
check_svc mattermost     "Mattermost (chat)"
check_svc n8n            "n8n (automation)"
check_svc openclaw       "OpenClaw gateway"
check_cmd openclaw       "openclaw CLI"
check_cmd ollama         "ollama CLI"
python3 -c "import faster_whisper" 2>/dev/null && \
  echo -e "  \033[1;32m✓\033[0m faster-whisper (voice)" || \
  echo -e "  \033[1;33m~\033[0m faster-whisper (voice – optional)"

echo ""
echo "  Service endpoints:"
echo "    OpenClaw Gateway:   http://${SERVER_HOSTNAME}:18789"
echo "    Mattermost Chat:    http://${SERVER_HOSTNAME}:8065"
echo "    n8n Automation:     http://${SERVER_HOSTNAME}:5678"
echo "    Mission Control:    http://${SERVER_HOSTNAME}:3001"
echo ""
echo "  Next steps:"
echo "    1. Browse to http://${SERVER_HOSTNAME}:8065 → create admin + bot account"
echo "    2. Run:  sudo openclaw-configure-mattermost <BOT_TOKEN>"
echo "    3. Edit: $OC_WORKSPACE/user.md   (tell agent who you are)"
echo "    4. Edit: $OC_WORKSPACE/SOUL.md   (personality & boundaries)"
echo "    5. Edit: $OC_WORKSPACE/HEARTBEAT.md (what to check every 30min)"
echo "    6. Test:  openclaw agent --message 'Hello, are you there?'"
echo ""
echo "  Logs:"
echo "    journalctl -u openclaw  -f"
echo "    journalctl -u ollama    -f"
echo "    journalctl -u mattermost -f"
echo ""
