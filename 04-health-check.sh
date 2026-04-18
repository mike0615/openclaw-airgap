#!/usr/bin/env bash
# =============================================================================
# OpenClaw Health Check Script
# =============================================================================
# Usage:
#   bash 04-health-check.sh [--verbose]
#
# Exit codes:
#   0 — all checks green
#   1 — one or more checks red (critical failures)
# =============================================================================

set -euo pipefail

# ── Color codes ───────────────────────────────────────────────────────────────
RED='\033[1;31m'
GRN='\033[1;32m'
YLW='\033[1;33m'
BLU='\033[1;34m'
CYN='\033[1;36m'
RST='\033[0m'

VERBOSE=false
FAILURES=0
WARNINGS=0

# ── Parse arguments ───────────────────────────────────────────────────────────
for arg in "$@"; do
  case "$arg" in
    --verbose|-v) VERBOSE=true ;;
    --help|-h)
      echo "Usage: bash 04-health-check.sh [--verbose]"
      echo ""
      echo "Options:"
      echo "  --verbose, -v   Show extra detail for each check"
      echo "  --help, -h      Show this help and exit"
      echo ""
      echo "Exit code 0 = all green; exit code 1 = one or more red."
      exit 0
      ;;
  esac
done

# ── Output helpers ────────────────────────────────────────────────────────────
ok()     { echo -e "  ${GRN}✓${RST} $*"; }
fail()   { echo -e "  ${RED}✗${RST} $*"; (( FAILURES++ )) || true; }
warn()   { echo -e "  ${YLW}!${RST} $*"; (( WARNINGS++ )) || true; }
info()   { echo -e "  ${BLU}i${RST} $*"; }
verbose(){ $VERBOSE && echo -e "    ${BLU}»${RST} $*" || true; }
section(){ echo ""; echo -e "${CYN}── $* ──${RST}"; }

echo ""
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║              OpenClaw Health Check                           ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo " $(date)"

# ─── Services ─────────────────────────────────────────────────────────────────
section "Services"

check_service() {
  local svc="$1"
  local label="$2"
  if systemctl is-active --quiet "$svc" 2>/dev/null; then
    local restarts
    restarts=$(systemctl show "$svc" --property=NRestarts --value 2>/dev/null || echo "?")
    ok "${label} (restarts today: ${restarts})"
    verbose "$(systemctl status "$svc" --no-pager -l 2>/dev/null | head -5)"
  else
    fail "${label} — not running"
    info "Check: journalctl -u ${svc} -n 30 --no-pager"
  fi
}

check_service postgresql-16  "PostgreSQL 16"
check_service ollama          "Ollama"
check_service mattermost      "Mattermost"
check_service n8n             "n8n"
check_service openclaw        "OpenClaw gateway"

# ─── HTTP Endpoints ───────────────────────────────────────────────────────────
section "HTTP Health Endpoints"

check_http() {
  local url="$1"
  local label="$2"
  local timeout="${3:-5}"
  if curl -sf --max-time "$timeout" "$url" >/dev/null 2>&1; then
    ok "$label → $url"
  else
    fail "$label — no response at $url"
  fi
}

check_http "http://localhost:11434/api/tags"           "Ollama API"          10
check_http "http://localhost:8065/api/v4/system/ping"  "Mattermost API"      10
check_http "http://localhost:5678/healthz"             "n8n health"          10
check_http "http://localhost:18789/health"             "OpenClaw gateway"    10
check_http "http://localhost:3001"                     "Mission Control"     5 || \
  warn "Mission Control dashboard not responding (optional)"

# ─── Ollama Model ─────────────────────────────────────────────────────────────
section "Ollama Model Status"

OLLAMA_RESPONSE=$(curl -s --max-time 10 http://localhost:11434/api/tags 2>/dev/null || echo "")
if [[ -n "$OLLAMA_RESPONSE" ]]; then
  MODEL_INFO=$(echo "$OLLAMA_RESPONSE" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    models = data.get('models', [])
    if models:
        names = [m['name'] for m in models]
        print(f'{len(models)} model(s): {names}')
    else:
        print('0 models loaded')
except Exception as e:
    print(f'parse error: {e}')
" 2>/dev/null || echo "parse error")
  if echo "$MODEL_INFO" | grep -q "^0 models"; then
    fail "No Ollama models loaded — pull a model first"
    info "Run: OLLAMA_HOST=localhost ollama pull qwen2.5:14b"
  else
    ok "Ollama models: $MODEL_INFO"
  fi
else
  fail "Cannot reach Ollama API to check models"
fi

# ─── PostgreSQL ───────────────────────────────────────────────────────────────
section "PostgreSQL"

if command -v pg_isready >/dev/null 2>&1; then
  if pg_isready -q; then
    ok "PostgreSQL accepting connections"
  else
    fail "PostgreSQL not accepting connections"
  fi
fi

if [[ "$(id -u)" -eq 0 ]] || sudo -n -u postgres true 2>/dev/null; then
  DB_LIST=$(sudo -u postgres psql -c '\l' 2>/dev/null | grep -E "mattermost|openclaw" | awk '{print $1}' | tr '\n' ' ' || echo "")
  if echo "$DB_LIST" | grep -q "mattermost"; then
    ok "Mattermost database exists"
  else
    fail "Mattermost database not found — check PostgreSQL setup"
  fi
  verbose "Databases: $DB_LIST"
else
  warn "Cannot check PostgreSQL databases — run as root for full check"
fi

# ─── Credentials and Config Files ────────────────────────────────────────────
section "Credentials & Configuration"

# n8n env file
if [[ -f /etc/openclaw/n8n.env ]]; then
  N8N_PERMS=$(stat -c "%a" /etc/openclaw/n8n.env 2>/dev/null)
  ok "n8n credentials file: /etc/openclaw/n8n.env (perms: $N8N_PERMS)"
  if [[ "$N8N_PERMS" != "600" ]]; then
    warn "n8n.env permissions are $N8N_PERMS — should be 600"
    info "Fix: chmod 600 /etc/openclaw/n8n.env"
  fi
else
  fail "n8n credentials file missing: /etc/openclaw/n8n.env"
  info "Run: 02-install.sh --force  or create manually"
fi

# Mattermost DB creds
if [[ -f /root/.mattermost-db-creds ]]; then
  ok "Mattermost DB credentials: /root/.mattermost-db-creds"
else
  warn "Mattermost DB credentials not found at /root/.mattermost-db-creds"
fi

# openclaw.json
OC_CONFIG="/opt/openclaw/.openclaw/openclaw.json"
if [[ -f "$OC_CONFIG" ]]; then
  ok "OpenClaw config: $OC_CONFIG"

  # Check for unconfigured bot token
  BOT_TOKEN=$(python3 -c "
import json, re
try:
    with open('$OC_CONFIG') as f:
        content = re.sub(r'//[^\n]*', '', f.read())
    cfg = json.loads(content)
    print(cfg.get('channels', {}).get('mattermost', {}).get('botToken', ''))
except: print('')
" 2>/dev/null || echo "")
  if [[ "$BOT_TOKEN" == "PASTE_BOT_TOKEN_HERE" ]] || [[ -z "$BOT_TOKEN" ]]; then
    warn "Mattermost bot token not configured"
    info "Run: sudo openclaw-configure-mattermost <TOKEN>"
  else
    ok "Mattermost bot token configured"
  fi
else
  fail "OpenClaw config not found: $OC_CONFIG"
fi

# ─── Identity Files — Placeholder Check ──────────────────────────────────────
section "Identity Files"

OC_WORKSPACE="/opt/openclaw/workspace"
if [[ -d "$OC_WORKSPACE" ]]; then
  PLACEHOLDER_FILES=()
  for f in "$OC_WORKSPACE/SOUL.md" "$OC_WORKSPACE/user.md" "$OC_WORKSPACE/memory.md"; do
    if [[ -f "$f" ]]; then
      if grep -q "__[A-Z_]*__" "$f" 2>/dev/null; then
        PLACEHOLDER_FILES+=("$(basename "$f")")
      fi
    fi
  done

  if [[ "${#PLACEHOLDER_FILES[@]}" -gt 0 ]]; then
    warn "Identity files still contain placeholder text: ${PLACEHOLDER_FILES[*]}"
    info "Run: sudo bash 03-configure-identity.sh"
  else
    ok "Identity files: no unresolved placeholders"
  fi

  for f in SOUL.md user.md memory.md HEARTBEAT.md AGENTS.md TOOLS.md; do
    if [[ -f "$OC_WORKSPACE/$f" ]]; then
      verbose "Found: $OC_WORKSPACE/$f"
    else
      warn "Missing identity file: $OC_WORKSPACE/$f"
    fi
  done
else
  fail "Workspace directory not found: $OC_WORKSPACE"
fi

# ─── Disk Usage ───────────────────────────────────────────────────────────────
section "Disk Usage"

while IFS= read -r line; do
  USAGE=$(echo "$line" | awk '{print $5}' | tr -d '%')
  MOUNT=$(echo "$line" | awk '{print $6}')
  USED=$(echo "$line" | awk '{print $3}')
  AVAIL=$(echo "$line" | awk '{print $4}')
  if [[ "$USAGE" -ge 90 ]]; then
    fail "Disk: $MOUNT — ${USAGE}% used (${USED} used, ${AVAIL} free) CRITICAL"
  elif [[ "$USAGE" -ge 80 ]]; then
    warn "Disk: $MOUNT — ${USAGE}% used (${USED} used, ${AVAIL} free)"
  else
    ok "Disk: $MOUNT — ${USAGE}% used (${AVAIL} free)"
  fi
done < <(df -h --output=size,used,avail,pcent,target 2>/dev/null | tail -n +2 | \
  grep -E '^[^T]' | awk '{print NR, $2, $3, $4, $5}' | \
  while read -r n size used avail pcent; do echo "$size $used $avail $pcent /$(df -h 2>/dev/null | awk "NR==$(( n+1 )) {print \$6}")"; done 2>/dev/null) 2>/dev/null || \
df -h 2>/dev/null | tail -n +2 | while read -r fs size used avail pct mount; do
  PCT="${pct//%/}"
  if [[ "$PCT" =~ ^[0-9]+$ ]]; then
    if [[ "$PCT" -ge 90 ]]; then
      fail "Disk: $mount — ${PCT}% used CRITICAL"
    elif [[ "$PCT" -ge 80 ]]; then
      warn "Disk: $mount — ${PCT}% used (${avail} free)"
    else
      ok "Disk: $mount — ${PCT}% used (${avail} free)"
    fi
  fi
done

# ─── Log File Sizes ───────────────────────────────────────────────────────────
section "Log Files"

LOG_DIR="/var/log/openclaw"
if [[ -d "$LOG_DIR" ]]; then
  while IFS= read -r logfile; do
    SIZE_BYTES=$(stat -c%s "$logfile" 2>/dev/null || echo 0)
    SIZE_MB=$(( SIZE_BYTES / 1024 / 1024 ))
    BASENAME=$(basename "$logfile")
    if [[ "$SIZE_MB" -ge 100 ]]; then
      warn "Log file large: $BASENAME — ${SIZE_MB}MB (consider rotation)"
    else
      ok "Log: $BASENAME — ${SIZE_MB}MB"
      verbose "Path: $logfile"
    fi
  done < <(find "$LOG_DIR" -name "*.log" -type f 2>/dev/null)
  [[ -z "$(ls "$LOG_DIR"/*.log 2>/dev/null)" ]] && info "No log files found in $LOG_DIR yet"
else
  warn "Log directory not found: $LOG_DIR"
fi

# ─── Last Backup ─────────────────────────────────────────────────────────────
section "Backup Status"

BACKUP_DIR="/opt/openclaw/backups"
if [[ -d "$BACKUP_DIR" ]]; then
  LATEST_BACKUP=$(find "$BACKUP_DIR" -name "*.tar.gz" -type f -printf '%T@ %p\n' 2>/dev/null | \
    sort -n | tail -1 | awk '{print $2}')
  if [[ -n "$LATEST_BACKUP" ]]; then
    BACKUP_DATE=$(stat -c%y "$LATEST_BACKUP" 2>/dev/null | cut -d' ' -f1)
    BACKUP_SIZE=$(du -sh "$LATEST_BACKUP" 2>/dev/null | cut -f1)
    ok "Last workspace backup: $BACKUP_DATE ($BACKUP_SIZE) — $(basename "$LATEST_BACKUP")"
  else
    warn "No workspace backups found in $BACKUP_DIR"
    info "Backups are created by the workspace-backup heartbeat task"
  fi
fi

if [[ -f /var/log/backup.log ]]; then
  LAST_LINE=$(tail -1 /var/log/backup.log 2>/dev/null || echo "")
  LAST_DATE=$(head -1 <(grep -oP '\d{4}-\d{2}-\d{2}' /var/log/backup.log | tail -1) 2>/dev/null || echo "unknown")
  if echo "$LAST_LINE" | grep -qi "error\|fail"; then
    fail "Last backup log entry shows error: $LAST_LINE"
  else
    ok "Backup log: last entry — ${LAST_DATE}"
  fi
else
  info "No /var/log/backup.log found — system backup may not be configured"
fi

# ─── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════"
if [[ "$FAILURES" -eq 0 ]] && [[ "$WARNINGS" -eq 0 ]]; then
  echo -e " ${GRN}All checks passed.${RST} OpenClaw is healthy."
elif [[ "$FAILURES" -eq 0 ]]; then
  echo -e " ${YLW}${WARNINGS} warning(s)${RST}, no critical failures. System is functional."
else
  echo -e " ${RED}${FAILURES} failure(s)${RST}, ${WARNINGS} warning(s). Attention required."
fi
echo ""
echo " Run with --verbose for additional detail."
echo " Full logs: journalctl -u openclaw -u ollama -u mattermost -u n8n -n 20"
echo "═══════════════════════════════════════════════════════════════"
echo ""

[[ "$FAILURES" -eq 0 ]]
