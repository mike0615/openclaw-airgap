#!/usr/bin/env bash
# configure-trixie.sh — Apply Trixie identity and integrations to this server.
# Run AFTER 02-install.sh. Server-only — do not commit personalised values to git.
#
# Usage: sudo bash configure-trixie.sh [--agentmail-key KEY] [--discord-token TOKEN]
set -euo pipefail

log()  { echo -e "\033[1;32m[+]\033[0m $*"; }
warn() { echo -e "\033[1;33m[!]\033[0m $*"; }
die()  { echo -e "\033[1;31m[✗]\033[0m $*" >&2; exit 1; }

[[ "$(id -u)" -eq 0 ]] || die "Run as root or with sudo."

WORKSPACE="${OC_WORKSPACE:-/opt/openclaw/workspace}"
OC_CONFIG="/opt/openclaw/.openclaw/openclaw.json"
ENV_FILE="/opt/openclaw/.openclaw/trixie.env"
AGENT_USER="openclaw"

AGENTMAIL_KEY=""
DISCORD_TOKEN=""
DISCORD_GUILD_ID=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --agentmail-key)  AGENTMAIL_KEY="$2";    shift 2 ;;
    --discord-token)  DISCORD_TOKEN="$2";    shift 2 ;;
    --discord-guild)  DISCORD_GUILD_ID="$2"; shift 2 ;;
    *) die "Unknown arg: $1" ;;
  esac
done

[[ -d "$WORKSPACE" ]] || die "Workspace not found: $WORKSPACE — run 02-install.sh first."

echo ""
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║           Trixie Identity Configuration                      ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""

# ── 1. Apply SOUL.md ─────────────────────────────────────────────────────────
log "Installing Trixie SOUL.md..."
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOUL_SRC="$SCRIPT_DIR/configs/identity/SOUL-trixie.md"
[[ -f "$SOUL_SRC" ]] || die "SOUL-trixie.md not found at $SOUL_SRC"
cp "$SOUL_SRC" "$WORKSPACE/SOUL.md"
log "  SOUL.md → $WORKSPACE/SOUL.md"

# ── 2. Apply user.md ─────────────────────────────────────────────────────────
log "Writing user.md for Mike..."
TODAY=$(date +%Y-%m-%d)
cat > "$WORKSPACE/user.md" << USERMD
# User Profile — Mike

> Configured by configure-trixie.sh on ${TODAY}.

## Identity

- **Name:** Mike
- **Preferred name:** Mike
- **Time zone:** America/New_York
- **Working hours:** 07:00–22:00 M-Su
- **Role:** Systems Engineer / Lab Operator

## Current Projects

- openclaw-airgap: self-hosted AI agent stack (this server)
- lrn-netsniff: multi-point network capture and analysis tool
- mikes-wiki: self-hosted Wiki.js instance

## Tools I Use

- Rocky Linux 9, systemd, firewalld
- Docker, Git, Ansible
- Python, Bash

## Communication Preferences

- Brevity: prefer short, direct answers; offer to go deeper if needed
- Format: bullets for lists, prose for context
- Code: full files when making changes, diffs for reviews

## Things the Agent Should Know

- This server is internet-connected and Trixie has her own email.
- Mike's contact email: mike@andersoncomputer.us
- Agent email: trixie-openclaw@agentmail.to

## What NOT to Bother Me With

- Routine HEARTBEAT_OK messages (only notify if something needs action)

---
*Updated: ${TODAY}*
USERMD

# ── 3. Write memory.md ───────────────────────────────────────────────────────
log "Seeding memory.md..."
HOSTNAME=$(hostname -f 2>/dev/null || hostname)
cat > "$WORKSPACE/memory.md" << MEMMD
# Permanent Memory

> Updated by configure-trixie.sh on $(date +%Y-%m-%d).
> Add permanent facts here. This file loads on every request.

## About This System

- Hostname: ${HOSTNAME}
- IP: $(hostname -I | awk '{print $1}')
- OS: Rocky Linux 9 (internet-connected)
- Model: llama3.1:8b via Ollama (http://127.0.0.1:11434)
- Workspace: ${WORKSPACE}

## About Me (Trixie)

- My name is Trixie. I respond to "Trixie".
- My email: trixie-openclaw@agentmail.to (via AgentMail)
- I have internet access and a Discord presence.
- I was configured on $(date +%Y-%m-%d).

## Key Contacts

- Mike (operator): mike@andersoncomputer.us

## Standing Notes

- (Add permanent facts and decisions here as they come up)
MEMMD

# ── 4. Write trixie.env (credentials — server-only) ─────────────────────────
log "Writing trixie.env..."
mkdir -p "$(dirname "$ENV_FILE")"
cat > "$ENV_FILE" << ENVFILE
# Trixie integration credentials — server-only, never commit to git
# Generated: $(date)

AGENT_NAME=Trixie
AGENT_EMAIL=trixie-openclaw@agentmail.to
ENVFILE

if [[ -n "$AGENTMAIL_KEY" ]]; then
  echo "AGENTMAIL_API_KEY=${AGENTMAIL_KEY}" >> "$ENV_FILE"
  log "  AgentMail key written"
else
  echo "# AGENTMAIL_API_KEY=am_us_..." >> "$ENV_FILE"
  warn "  AgentMail key not set — edit $ENV_FILE and add AGENTMAIL_API_KEY"
fi

if [[ -n "$DISCORD_TOKEN" ]]; then
  echo "DISCORD_BOT_TOKEN=${DISCORD_TOKEN}" >> "$ENV_FILE"
  log "  Discord bot token written"
else
  echo "# DISCORD_BOT_TOKEN=..." >> "$ENV_FILE"
  warn "  Discord bot token not set — add DISCORD_BOT_TOKEN to $ENV_FILE when ready"
fi

if [[ -n "$DISCORD_GUILD_ID" ]]; then
  echo "DISCORD_GUILD_ID=${DISCORD_GUILD_ID}" >> "$ENV_FILE"
fi

chmod 640 "$ENV_FILE"
chown root:"$AGENT_USER" "$ENV_FILE" 2>/dev/null || true

# ── 5. Patch openclaw.json — update active hours + gateway ───────────────────
if [[ -f "$OC_CONFIG" ]]; then
  log "Patching openclaw.json..."
  python3 - << PYCFG
import json, re
try:
    with open("${OC_CONFIG}", "r") as f:
        content = re.sub(r'//[^\n]*', '', f.read())
    cfg = json.loads(content)

    hb = cfg.setdefault("agents", {}).setdefault("defaults", {}).setdefault("heartbeat", {})
    ah = hb.setdefault("activeHours", {})
    ah["tz"]    = "America/New_York"
    ah["start"] = "07:00"
    ah["end"]   = "22:00"

    # Open gateway to LAN (firewall restricts access)
    cfg.setdefault("gateway", {})["host"] = "0.0.0.0"

    with open("${OC_CONFIG}", "w") as f:
        json.dump(cfg, f, indent=2)
    print("  openclaw.json patched")
except Exception as e:
    print(f"  Warning: {e}")
PYCFG
fi

# ── 6. Fix ownership ─────────────────────────────────────────────────────────
chown -R "$AGENT_USER:$AGENT_USER" "$WORKSPACE" 2>/dev/null || true

# ── 7. Restart openclaw ──────────────────────────────────────────────────────
if systemctl is-enabled --quiet openclaw 2>/dev/null; then
  log "Restarting openclaw service..."
  systemctl restart openclaw
fi

# ── Summary ──────────────────────────────────────────────────────────────────
IP=$(hostname -I | awk '{print $1}')
echo ""
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║           Trixie is configured!                              ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""
log "Agent name:  Trixie"
log "Email:       trixie-openclaw@agentmail.to"
log "Workspace:   $WORKSPACE"
log "Env file:    $ENV_FILE"
echo ""
echo "  Mattermost: http://${IP}:8065"
echo "  OpenClaw:   http://${IP}:18789"
echo ""
echo "  Next:"
echo "    1. Edit $ENV_FILE — add AGENTMAIL_API_KEY and DISCORD_BOT_TOKEN"
echo "    2. Set up Mattermost bot account, then: openclaw-configure-mattermost <BOT_TOKEN>"
echo "    3. Test: openclaw agent --message 'Hello, what is your name?'"
echo "    4. Run: bash 04-health-check.sh"
echo ""
