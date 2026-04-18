#!/usr/bin/env bash
# =============================================================================
# OpenClaw Identity Configuration Wizard
# =============================================================================
# Run AFTER 02-install.sh to personalize your agent.
#
# Usage:
#   sudo bash 03-configure-identity.sh [--workspace /opt/openclaw/workspace]
#
# What this does:
#   1. Asks for agent name, user info, timezone, working hours, etc.
#   2. Writes values into SOUL.md, user.md, and openclaw.json
#   3. Configures heartbeat tasks interactively
#   4. Restarts openclaw service
# =============================================================================

set -euo pipefail

# ── Helpers ───────────────────────────────────────────────────────────────────
log()    { echo -e "\033[1;32m[+]\033[0m $*"; }
info()   { echo -e "\033[1;34m[i]\033[0m $*"; }
warn()   { echo -e "\033[1;33m[!]\033[0m $*"; }
die()    { echo -e "\033[1;31m[✗]\033[0m $*" >&2; exit 1; }
prompt() { echo -e "\033[1;36m[?]\033[0m $*"; }
section(){ echo ""; echo -e "\033[1;35m━━━ $* ━━━\033[0m"; }

# ── Parse arguments ───────────────────────────────────────────────────────────
OC_WORKSPACE=""
OC_CONFIG_FILE=""

usage() {
  cat << 'USAGE'
Usage: sudo bash 03-configure-identity.sh [OPTIONS]

Interactive wizard to personalize your OpenClaw agent identity.
Run this after completing 02-install.sh.

Options:
  --workspace PATH    Path to OpenClaw workspace (default: auto-detect)
  --config FILE       Path to openclaw.json (default: auto-detect)
  --help              Show this help and exit
USAGE
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h)    usage ;;
    --workspace)  OC_WORKSPACE="$2"; shift 2 ;;
    --config)     OC_CONFIG_FILE="$2"; shift 2 ;;
    *)            die "Unknown argument: $1 (use --help)" ;;
  esac
done

# ── Detect paths ──────────────────────────────────────────────────────────────
[[ "$(id -u)" -eq 0 ]] || die "Run as root or with sudo."

# Auto-detect workspace from openclaw.json if not specified
if [[ -z "$OC_WORKSPACE" ]]; then
  if [[ -z "$OC_CONFIG_FILE" ]]; then
    for candidate in /opt/openclaw/.openclaw/openclaw.json /etc/openclaw/openclaw.json; do
      [[ -f "$candidate" ]] && OC_CONFIG_FILE="$candidate" && break
    done
  fi
  if [[ -n "$OC_CONFIG_FILE" ]] && [[ -f "$OC_CONFIG_FILE" ]]; then
    OC_WORKSPACE=$(python3 -c "
import json, sys
try:
    with open('$OC_CONFIG_FILE') as f:
        # Strip JSON5-style comments
        import re
        content = re.sub(r'//[^\n]*', '', f.read())
        cfg = json.loads(content)
    print(cfg.get('workspace', ''))
except Exception as e:
    print('')
" 2>/dev/null || echo "")
  fi
  [[ -z "$OC_WORKSPACE" ]] && OC_WORKSPACE="/opt/openclaw/workspace"
fi

[[ -d "$OC_WORKSPACE" ]] || die "Workspace directory not found: $OC_WORKSPACE\nRun 02-install.sh first."

# Detect agent user from workspace ownership
AGENT_USER=$(stat -c '%U' "$OC_WORKSPACE" 2>/dev/null || echo "openclaw")

# Locate the openclaw config
if [[ -z "$OC_CONFIG_FILE" ]]; then
  OC_CONFIG_FILE="/opt/openclaw/.openclaw/openclaw.json"
fi

SOUL_FILE="$OC_WORKSPACE/SOUL.md"
USER_FILE="$OC_WORKSPACE/user.md"
MEMORY_FILE="$OC_WORKSPACE/memory.md"
HEARTBEAT_FILE="$OC_WORKSPACE/HEARTBEAT.md"

for f in "$SOUL_FILE" "$USER_FILE" "$HEARTBEAT_FILE"; do
  [[ -f "$f" ]] || die "Required file not found: $f\nRun 02-install.sh first."
done

# ── Banner ────────────────────────────────────────────────────────────────────
echo ""
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║         OpenClaw Identity Configuration Wizard               ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""
info "Workspace: $OC_WORKSPACE"
info "Config:    $OC_CONFIG_FILE"
echo ""
echo "This wizard will personalize your agent's identity files."
echo "Press Enter to accept defaults shown in [brackets]."
echo ""
read -rp "Ready to begin? [y/N] " _START
[[ "${_START,,}" == "y" ]] || { echo "Aborted."; exit 0; }

# ─── Section 1: Agent Identity ────────────────────────────────────────────────
section "1. Agent Identity"

prompt "What should your agent be called? (e.g., Atlas, Max, CLAW) [CAT]:"
read -r AGENT_NAME
AGENT_NAME="${AGENT_NAME:-CAT}"

prompt "What's the agent's role/title? [AI Operations Agent]:"
read -r AGENT_ROLE
AGENT_ROLE="${AGENT_ROLE:-AI Operations Agent}"

# ─── Section 2: User/Operator Identity ────────────────────────────────────────
section "2. Your Identity (the operator)"

prompt "Your full name [Operator]:"
read -r USER_NAME
USER_NAME="${USER_NAME:-Operator}"

prompt "Your callsign/preferred name (how the agent addresses you) [$USER_NAME]:"
read -r USER_CALLSIGN
USER_CALLSIGN="${USER_CALLSIGN:-$USER_NAME}"

prompt "Your role/title [Systems Engineer]:"
read -r USER_ROLE
USER_ROLE="${USER_ROLE:-Systems Engineer}"

# ─── Section 3: Timezone ─────────────────────────────────────────────────────
section "3. Timezone"
echo ""
echo "  Common options:"
echo "    1) America/New_York    (US East)"
echo "    2) America/Chicago     (US Central)"
echo "    3) America/Denver      (US Mountain)"
echo "    4) America/Los_Angeles (US Pacific)"
echo "    5) America/Anchorage   (US Alaska)"
echo "    6) Pacific/Honolulu    (US Hawaii)"
echo "    7) Europe/London"
echo "    8) Europe/Berlin"
echo "    9) Asia/Tokyo"
echo "   10) UTC"
echo "   11) Enter custom timezone"
echo ""
prompt "Select timezone [1]:"
read -r TZ_CHOICE
TZ_CHOICE="${TZ_CHOICE:-1}"

case "$TZ_CHOICE" in
  1)  USER_TZ="America/New_York" ;;
  2)  USER_TZ="America/Chicago" ;;
  3)  USER_TZ="America/Denver" ;;
  4)  USER_TZ="America/Los_Angeles" ;;
  5)  USER_TZ="America/Anchorage" ;;
  6)  USER_TZ="Pacific/Honolulu" ;;
  7)  USER_TZ="Europe/London" ;;
  8)  USER_TZ="Europe/Berlin" ;;
  9)  USER_TZ="Asia/Tokyo" ;;
  10) USER_TZ="UTC" ;;
  11) prompt "Enter timezone (e.g., America/Phoenix):"; read -r USER_TZ; USER_TZ="${USER_TZ:-UTC}" ;;
  *)  USER_TZ="America/New_York" ;;
esac
log "Timezone: $USER_TZ"

# ─── Section 4: Working Hours ─────────────────────────────────────────────────
section "4. Working Hours"

prompt "Working hours start (24h, e.g., 07:00) [07:00]:"
read -r WORK_START
WORK_START="${WORK_START:-07:00}"

prompt "Working hours end (24h, e.g., 18:00) [18:00]:"
read -r WORK_END
WORK_END="${WORK_END:-18:00}"

prompt "Working days (e.g., M-F, M-Su) [M-F]:"
read -r WORK_DAYS
WORK_DAYS="${WORK_DAYS:-M-F}"

# ─── Section 5: Current Projects ─────────────────────────────────────────────
section "5. Current Projects (tell the agent what you're working on)"

prompt "Project 1 — one sentence description [Infrastructure automation]:"
read -r PROJECT_1
PROJECT_1="${PROJECT_1:-Infrastructure automation}"

prompt "Project 2 — one sentence description [leave blank to skip]:"
read -r PROJECT_2

prompt "Project 3 — one sentence description [leave blank to skip]:"
read -r PROJECT_3

# ─── Section 6: Communication Style ─────────────────────────────────────────
section "6. Communication Style"
echo ""
echo "  1) Short — direct answers, minimal context"
echo "  2) Full  — detailed explanations, more context"
echo ""
prompt "Preferred response style [1]:"
read -r COMM_STYLE_CHOICE
COMM_STYLE_CHOICE="${COMM_STYLE_CHOICE:-1}"
case "$COMM_STYLE_CHOICE" in
  2) COMM_STYLE="prefer full context and detailed explanations" ;;
  *) COMM_STYLE="prefer short, direct answers; offer to go deeper if needed" ;;
esac

# ─── Section 7: Morning Briefing Time ────────────────────────────────────────
section "7. Morning Briefing"

prompt "Time for morning briefing (24h, e.g., 07:30) [07:30]:"
read -r BRIEFING_TIME
BRIEFING_TIME="${BRIEFING_TIME:-07:30}"

# ─── Section 8: Heartbeat Tasks ──────────────────────────────────────────────
section "8. Heartbeat Tasks"
echo ""
echo "Which background tasks do you want enabled?"
echo "(These run automatically. You can edit HEARTBEAT.md later for fine-tuning.)"
echo ""

prompt "Enable backup-check? Alerts if no backup in 25h. [Y/n]:"
read -r ENABLE_BACKUP
ENABLE_BACKUP="${ENABLE_BACKUP:-y}"

prompt "Enable security-scan? Checks failed SSH logins daily at 03:00. [Y/n]:"
read -r ENABLE_SECURITY
ENABLE_SECURITY="${ENABLE_SECURITY:-y}"

prompt "Enable service-restart-alert? Alerts if services restart too often. [Y/n]:"
read -r ENABLE_RESTART_ALERT
ENABLE_RESTART_ALERT="${ENABLE_RESTART_ALERT:-y}"

prompt "Enable workspace-backup? Daily backup of memory to /opt/openclaw/backups/. [Y/n]:"
read -r ENABLE_WS_BACKUP
ENABLE_WS_BACKUP="${ENABLE_WS_BACKUP:-y}"

# ─── Write SOUL.md ────────────────────────────────────────────────────────────
section "Writing identity files..."

log "Updating SOUL.md..."
sed -i "s|__AGENT_NAME__|${AGENT_NAME}|g" "$SOUL_FILE"
sed -i "s|__USER_NAME__|${USER_CALLSIGN}|g" "$SOUL_FILE"
sed -i "s|__WORKSPACE__|${OC_WORKSPACE}|g" "$SOUL_FILE"

# ─── Write user.md ────────────────────────────────────────────────────────────
log "Updating user.md..."
TODAY=$(date +%Y-%m-%d)

cat > "$USER_FILE" << USERMD
# User Profile — ${USER_NAME}

> Configured by 03-configure-identity.sh on ${TODAY}.
> Edit this file to update your profile at any time.

## Identity

- **Name:** ${USER_NAME}
- **Preferred name / callsign:** ${USER_CALLSIGN}
- **Time zone:** ${USER_TZ}
- **Working hours:** ${WORK_START}–${WORK_END} ${WORK_DAYS}
- **Role:** ${USER_ROLE}

## Role & Responsibilities

- ${USER_ROLE} (update with specifics)
- (What decisions land on your desk?)
- (What are you accountable for that you want the agent to help with?)

## Current Projects

- ${PROJECT_1}
USERMD

[[ -n "$PROJECT_2" ]] && echo "- ${PROJECT_2}" >> "$USER_FILE"
[[ -n "$PROJECT_3" ]] && echo "- ${PROJECT_3}" >> "$USER_FILE"

cat >> "$USER_FILE" << USERMD2

## Tools I Use

- Rocky Linux 9, systemd, firewalld
- (Add your specific tools: FreeIPA, XCP-ng, Ansible, Git, etc.)
- (What repos or directories on this system matter most?)

## Communication Preferences

- Brevity: ${COMM_STYLE}
- Format: prefer bullets for lists, prose for context
- Code:   show full files when making changes; diffs for reviews

## Things the Agent Should Know

- This system is air-gapped by design — no internet access.
- (Standing context that would otherwise repeat in every conversation)
- (Past decisions or constraints that shape current work)

## What NOT to Bother Me With

- Routine HEARTBEAT_OK status messages (only notify if something needs action)
- (Other low-priority items the agent can handle autonomously)

---
*Updated: ${TODAY}*
USERMD2

# ─── Update memory.md ─────────────────────────────────────────────────────────
if [[ -f "$MEMORY_FILE" ]]; then
  log "Updating memory.md..."
  sed -i "s|__USER_NAME__|${USER_NAME}|g"          "$MEMORY_FILE"
  sed -i "s|__MODEL__|$(grep -o '__MODEL__' "$MEMORY_FILE" | head -1)|g" "$MEMORY_FILE" 2>/dev/null || true
  HOSTNAME=$(hostname -f 2>/dev/null || hostname)
  sed -i "s|(this machine's hostname)|${HOSTNAME}|g" "$MEMORY_FILE"
fi

# ─── Update openclaw.json heartbeat timezone ─────────────────────────────────
if [[ -f "$OC_CONFIG_FILE" ]]; then
  log "Updating openclaw.json (heartbeat timezone, briefing time)..."
  python3 - << PYCFG
import json, re

try:
    with open("${OC_CONFIG_FILE}", "r") as f:
        content = re.sub(r'//[^\n]*', '', f.read())
    cfg = json.loads(content)

    # Update heartbeat timezone
    hb = cfg.setdefault("agents", {}).setdefault("defaults", {}).setdefault("heartbeat", {})
    ah = hb.setdefault("activeHours", {})
    ah["tz"] = "${USER_TZ}"
    ah["start"] = "${WORK_START}"
    ah["end"] = "${WORK_END}"

    with open("${OC_CONFIG_FILE}", "w") as f:
        json.dump(cfg, f, indent=2)
    print("openclaw.json updated.")
except Exception as e:
    print(f"Warning: could not update openclaw.json: {e}")
PYCFG
fi

# ─── Write HEARTBEAT.md ───────────────────────────────────────────────────────
log "Updating HEARTBEAT.md..."

cat > "$HEARTBEAT_FILE" << HEARTBEATMD
# Heartbeat Checklist

> This runs every 30 minutes. The agent reads this, executes each task at its
> specified interval, and either acts or replies HEARTBEAT_OK.
>
> Configured by 03-configure-identity.sh on $(date +%Y-%m-%d).
> Edit this file to tune intervals and add new tasks.

tasks:

  - name: daily-log-init
    interval: 24h
    runAt: "${BRIEFING_TIME}"
    prompt: |
      Create today's daily log at memory/\$(date +%Y-%m-%d).md if it doesn't exist.
      Header: "# Daily Log — \$(date +%Y-%m-%d)\n\n## Actions\n\n## Notes\n"
      Then read yesterday's log and surface any unresolved items in a brief DM to ${USER_CALLSIGN}.

  - name: system-health
    interval: 1h
    prompt: |
      Run quick health checks:
      - All required services running? (openclaw, ollama, mattermost, n8n)
      - Disk usage > 85% on any partition?
      - Any failed systemd units?
      - RAM usage > 90%? (check with: free -m | awk 'NR==2{printf "%.0f%%", \$3*100/\$2}')
      If everything is fine, reply HEARTBEAT_OK.
      If anything needs attention, send a DM to ${USER_CALLSIGN} with specifics.

  - name: pending-tasks
    interval: 30m
    prompt: |
      Check workspace/tasks/ for any .md files with status: pending or blocked.
      If any task is stale (not updated in > 24h), surface it in a brief DM.
      If nothing is pending, reply HEARTBEAT_OK.

  - name: log-rotation-check
    interval: 24h
    runAt: "02:00"
    prompt: |
      Check /var/log/openclaw/ for log files > 100MB.
      Compress any logs older than 7 days.
      Report in the daily log only, do not DM unless total log size > 1GB.

HEARTBEATMD

# backup-check task
if [[ "${ENABLE_BACKUP,,}" =~ ^y ]]; then
cat >> "$HEARTBEAT_FILE" << 'BKPCHECK'
  - name: backup-check
    interval: 24h
    runAt: "06:00"
    prompt: |
      Check if /var/log/backup.log exists and has an entry from the last 25 hours.
      If found, verify the last line does not contain "ERROR" or "FAILED".
      If no backup log exists, warn: "No backup log found at /var/log/backup.log — backup may not be configured."
      If last backup was > 25h ago, send a DM with the time of last successful backup.
      If backup is current and clean, reply HEARTBEAT_OK.

BKPCHECK
fi

# security-scan task
if [[ "${ENABLE_SECURITY,,}" =~ ^y ]]; then
cat >> "$HEARTBEAT_FILE" << 'SECCHECK'
  - name: security-scan
    interval: 24h
    runAt: "03:00"
    prompt: |
      Check for failed SSH login attempts in the last 24 hours:
        grep "Failed password\|Invalid user" /var/log/secure 2>/dev/null | \
          grep "$(date -d '24 hours ago' +'%b %e')\|$(date +'%b %e')" | wc -l
      If the count exceeds 10, send a DM with the count and top 5 source IPs:
        grep "Failed password\|Invalid user" /var/log/secure 2>/dev/null | \
          grep -oP '(\d{1,3}\.){3}\d{1,3}' | sort | uniq -c | sort -rn | head -5
      If count is 10 or under, reply HEARTBEAT_OK.

SECCHECK
fi

# service-restart-alert task
if [[ "${ENABLE_RESTART_ALERT,,}" =~ ^y ]]; then
cat >> "$HEARTBEAT_FILE" << 'SVCRST'
  - name: service-restart-alert
    interval: 15m
    prompt: |
      Check if any openclaw-managed service has restarted more than 3 times today:
        for svc in openclaw ollama mattermost n8n; do
          COUNT=$(journalctl -u $svc --since "today" 2>/dev/null | grep -c "Started\|start" || echo 0)
          echo "$svc: $COUNT restarts today"
        done
      If any service has restarted more than 3 times, send a DM with the service name,
      restart count, and last 5 lines of its journal.
      Otherwise reply HEARTBEAT_OK.

SVCRST
fi

# workspace-backup task
if [[ "${ENABLE_WS_BACKUP,,}" =~ ^y ]]; then
cat >> "$HEARTBEAT_FILE" << WSBKP
  - name: workspace-backup
    interval: 24h
    runAt: "02:30"
    prompt: |
      Create a compressed backup of the memory directory:
        BACKUP_DIR="/opt/openclaw/backups"
        DATE=\$(date +%Y-%m-%d)
        mkdir -p "\$BACKUP_DIR"
        tar czf "\$BACKUP_DIR/\$DATE-memory.tar.gz" -C "${OC_WORKSPACE}" memory/ 2>/dev/null
        echo "Backup created: \$BACKUP_DIR/\$DATE-memory.tar.gz"
      Then remove backups older than 30 days:
        find "\$BACKUP_DIR" -name "*.tar.gz" -mtime +30 -delete
      Log the action in today's daily log. Reply HEARTBEAT_OK.

WSBKP
fi

cat >> "$HEARTBEAT_FILE" << 'EXAMPLES'
# ─── Future / opt-in tasks ───────────────────────────────────────────────────
# Uncomment and configure these after you set up the prerequisite components.

  # ── backup-check ─────────────────────────────────────────────────────────
  # Prerequisite: configure a system backup job that writes a status line to
  # /var/log/backup.log (e.g. via cron + rsync/restic/borgbackup).
  # See docs/ADVANCED.md "Backup and Restore Procedure" for an example script.
  # - name: backup-check
  #   interval: 24h
  #   runAt: "06:00"
  #   prompt: |
  #     Check if /var/log/backup.log exists and has an entry from the last 25 hours.
  #     If found, verify the last line does not contain "ERROR" or "FAILED".
  #     If no backup log exists, warn: "No backup log found at /var/log/backup.log —
  #     backup may not be configured."
  #     If last backup was > 25h ago, send a DM with the time of last successful backup.
  #     If backup is current and clean, reply HEARTBEAT_OK.

  # ── inbox-triage ─────────────────────────────────────────────────────────
  # Prerequisite: configure an AgentMail account or a local SMTP relay and
  # add its connection details to memory.md and openclaw.json.
  # - name: inbox-triage
  #   interval: 30m
  #   prompt: |
  #     Check the agent email inbox via AgentMail or local SMTP for new messages.
  #     Summarize anything actionable in a brief DM. Skip newsletters and FYIs.

  # ── news-brief ────────────────────────────────────────────────────────────
  # Prerequisite: install the morning-brief skill
  # (workspace/skills/morning-brief/SKILL.md) and list its sources in TOOLS.md.
  # - name: news-brief
  #   interval: 24h
  #   runAt: "07:30"
  #   prompt: |
  #     Using the morning-brief skill, scrape configured sources and send a
  #     morning briefing to the #briefings Mattermost channel.

  # ── trading-monitor ───────────────────────────────────────────────────────
  # Prerequisite: install the trading-monitor skill and configure brokerage
  # API access (local proxy or file-based feed) in TOOLS.md.
  # - name: trading-monitor
  #   interval: 6h
  #   activeHours: { start: "09:30", end: "16:00" }
  #   prompt: |
  #     Run the trading-monitor skill. Check open positions vs strategy rules.
  #     Report P&L and any required actions in the #trading Mattermost channel.
EXAMPLES

# ─── Fix ownership ────────────────────────────────────────────────────────────
chown -R "$AGENT_USER:$AGENT_USER" "$OC_WORKSPACE"
[[ -f "$OC_CONFIG_FILE" ]] && chown "$AGENT_USER:$AGENT_USER" "$OC_CONFIG_FILE" 2>/dev/null || true

# ─── Restart openclaw ────────────────────────────────────────────────────────
section "Restarting OpenClaw..."

if systemctl is-active --quiet openclaw 2>/dev/null; then
  systemctl restart openclaw
  log "OpenClaw restarted."
elif systemctl is-enabled --quiet openclaw 2>/dev/null; then
  systemctl start openclaw
  log "OpenClaw started."
else
  warn "OpenClaw service not found — skipping restart. Run: systemctl start openclaw"
fi

# ─── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║              Identity Configuration Complete                 ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""
log "Agent name: $AGENT_NAME"
log "Operator:   $USER_NAME ($USER_CALLSIGN)"
log "Timezone:   $USER_TZ"
log "Hours:      $WORK_START–$WORK_END $WORK_DAYS"
echo ""
info "Files updated:"
echo "  → $SOUL_FILE"
echo "  → $USER_FILE"
[[ -f "$MEMORY_FILE" ]] && echo "  → $MEMORY_FILE"
echo "  → $HEARTBEAT_FILE"
[[ -f "$OC_CONFIG_FILE" ]] && echo "  → $OC_CONFIG_FILE"
echo ""
info "Next steps:"
echo "  1. Review and edit $SOUL_FILE to refine personality"
echo "  2. Review and edit $USER_FILE to add more context"
echo "  3. Test: openclaw agent --message 'Hello, what is your name?'"
echo "  4. Run:  bash 04-health-check.sh"
echo ""
