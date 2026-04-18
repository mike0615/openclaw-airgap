#!/usr/bin/env bash
# =============================================================================
# OpenClaw Prerequisites Validation Script
# =============================================================================
# Run BEFORE 01-prepare-bundle.sh (on internet machine) or
# BEFORE 02-install.sh (on the air-gapped target machine).
#
# Usage:
#   bash 00-validate.sh
#   sudo bash 00-validate.sh   (some checks require root)
#
# Exit codes:
#   0 — all critical checks passed
#   1 — one or more critical checks failed
# =============================================================================

set -euo pipefail

# ── Color codes ───────────────────────────────────────────────────────────────
RED='\033[1;31m'
GRN='\033[1;32m'
YLW='\033[1;33m'
BLU='\033[1;34m'
CYN='\033[1;36m'
RST='\033[0m'

PASS="${GRN}[PASS]${RST}"
FAIL="${RED}[FAIL]${RST}"
WARN="${YLW}[WARN]${RST}"
INFO="${BLU}[INFO]${RST}"

CRITICAL_FAILURES=0

pass()  { echo -e "  ${PASS} $*"; }
fail()  { echo -e "  ${FAIL} $*"; (( CRITICAL_FAILURES++ )) || true; }
warn()  { echo -e "  ${WARN} $*"; }
info()  { echo -e "  ${INFO} $*"; }
header(){ echo -e "\n${CYN}── $* ──${RST}"; }

echo ""
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║         OpenClaw Prerequisites Validator                     ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""

# ─── Check: Running as root ──────────────────────────────────────────────────
header "Privileges"
if [[ "$(id -u)" -eq 0 ]]; then
  pass "Running as root"
else
  warn "Not running as root — some checks may be incomplete"
  info "Re-run with: sudo bash 00-validate.sh"
fi

# ─── Check: OS / Distribution ───────────────────────────────────────────────
header "Operating System"

OS_ID=""
OS_VER=""
if [[ -f /etc/os-release ]]; then
  OS_ID=$(. /etc/os-release && echo "${ID:-unknown}")
  OS_VER=$(. /etc/os-release && echo "${VERSION_ID:-unknown}")
fi

case "$OS_ID" in
  rocky|rhel|almalinux|centos)
    MAJOR_VER="${OS_VER%%.*}"
    if [[ "$MAJOR_VER" == "9" ]]; then
      pass "OS: ${OS_ID^} Linux ${OS_VER} (supported)"
    elif [[ "$MAJOR_VER" == "10" ]]; then
      warn "OS: ${OS_ID^} Linux ${OS_VER} — EL10 not fully tested; may work"
    else
      warn "OS: ${OS_ID^} Linux ${OS_VER} — expected version 9; RPMs may not match"
    fi
    ;;
  fedora)
    warn "OS: Fedora ${OS_VER} — bundle RPMs target RHEL9; use with caution"
    ;;
  ubuntu|debian)
    fail "OS: ${OS_ID^} ${OS_VER} — this bundle requires Rocky/RHEL 9 (uses dnf/rpm)"
    ;;
  *)
    warn "OS: ${OS_ID:-unknown} ${OS_VER} — not tested; proceed with caution"
    ;;
esac

# ─── Check: Architecture ────────────────────────────────────────────────────
header "Architecture"
ARCH=$(uname -m)
if [[ "$ARCH" == "x86_64" ]]; then
  pass "Architecture: x86_64 (required)"
else
  fail "Architecture: $ARCH — bundle requires x86_64 (amd64)"
fi

# ─── Check: Disk space ──────────────────────────────────────────────────────
header "Disk Space"
# Check /tmp for bundle prep (needs ~50GB)
TMP_AVAIL_KB=$(df -k /tmp 2>/dev/null | awk 'NR==2 {print $4}')
TMP_AVAIL_GB=$(( TMP_AVAIL_KB / 1024 / 1024 ))
if [[ "$TMP_AVAIL_GB" -ge 50 ]]; then
  pass "Disk space in /tmp: ${TMP_AVAIL_GB}GB available (≥50GB required)"
elif [[ "$TMP_AVAIL_GB" -ge 25 ]]; then
  warn "Disk space in /tmp: ${TMP_AVAIL_GB}GB — may be tight for large models"
else
  fail "Disk space in /tmp: ${TMP_AVAIL_GB}GB — need at least 50GB for bundle"
fi

# Check /opt for install target
OPT_AVAIL_KB=$(df -k /opt 2>/dev/null | awk 'NR==2 {print $4}')
OPT_AVAIL_GB=$(( OPT_AVAIL_KB / 1024 / 1024 ))
if [[ "$OPT_AVAIL_GB" -ge 30 ]]; then
  pass "Disk space in /opt: ${OPT_AVAIL_GB}GB available"
elif [[ "$OPT_AVAIL_GB" -ge 15 ]]; then
  warn "Disk space in /opt: ${OPT_AVAIL_GB}GB — may be tight; aim for 30GB+"
else
  fail "Disk space in /opt: ${OPT_AVAIL_GB}GB — need at least 30GB for installation"
fi

# ─── Check: RAM ─────────────────────────────────────────────────────────────
header "Memory"
RAM_KB=$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print $2}')
RAM_GB=$(( RAM_KB / 1024 / 1024 ))
if [[ "$RAM_GB" -ge 16 ]]; then
  pass "RAM: ${RAM_GB}GB (≥16GB required)"
elif [[ "$RAM_GB" -ge 10 ]]; then
  warn "RAM: ${RAM_GB}GB — minimum for small models (llama3.1:8b); 16GB+ recommended"
else
  fail "RAM: ${RAM_GB}GB — need at least 16GB for qwen2.5:14b (or 10GB for 8b model)"
fi

# ─── Check: Internet connectivity ───────────────────────────────────────────
header "Internet Connectivity"
if curl -sf --max-time 5 "https://google.com" >/dev/null 2>&1; then
  pass "Internet: HTTPS reachable (google.com)"
elif curl -sf --max-time 5 "http://google.com" >/dev/null 2>&1; then
  pass "Internet: HTTP reachable (google.com — HTTPS may be filtered)"
else
  warn "Internet: google.com not reachable — this may be the air-gapped target machine"
  info "If this is the PREP machine, you need internet access."
  info "If this is the TARGET machine, no internet is expected."
fi

if ping -c1 -W3 8.8.8.8 >/dev/null 2>&1; then
  pass "Internet: 8.8.8.8 pingable"
else
  warn "Internet: 8.8.8.8 not pingable (ICMP may be blocked or air-gapped)"
fi

# Check GitHub (required for bundle prep)
if curl -sf --max-time 10 "https://api.github.com" >/dev/null 2>&1; then
  pass "Internet: GitHub API reachable"
else
  warn "Internet: GitHub API not reachable — required for bundle prep (01-prepare-bundle.sh)"
fi

# ─── Check: Required commands ────────────────────────────────────────────────
header "Required Commands"
REQUIRED_CMDS=(curl git tar python3 dnf)
for cmd in "${REQUIRED_CMDS[@]}"; do
  if command -v "$cmd" >/dev/null 2>&1; then
    pass "Command: $cmd ($(command -v "$cmd"))"
  else
    fail "Command: $cmd — not found (install it first)"
  fi
done

# ─── Check: Optional commands ────────────────────────────────────────────────
header "Optional Commands"
OPTIONAL_CMDS=(podman docker createrepo_c jq openssl)
for cmd in "${OPTIONAL_CMDS[@]}"; do
  if command -v "$cmd" >/dev/null 2>&1; then
    pass "Optional: $cmd available"
  else
    info "Optional: $cmd not found (not required)"
  fi
done

# ─── Check: Node.js ─────────────────────────────────────────────────────────
header "Node.js"
if command -v node >/dev/null 2>&1; then
  NODE_VER=$(node --version 2>/dev/null || echo "unknown")
  NODE_MAJOR="${NODE_VER#v}"
  NODE_MAJOR="${NODE_MAJOR%%.*}"
  if [[ "$NODE_MAJOR" -ge 22 ]]; then
    pass "Node.js: $NODE_VER (v22+ recommended)"
  elif [[ "$NODE_MAJOR" -ge 18 ]]; then
    warn "Node.js: $NODE_VER — v22 recommended; older versions may work"
  else
    warn "Node.js: $NODE_VER — v22 required for OpenClaw; will be installed by bundle"
  fi
else
  info "Node.js: not installed — will be installed from bundle RPMs"
fi

# ─── Check: Ollama ──────────────────────────────────────────────────────────
header "Ollama"
if command -v ollama >/dev/null 2>&1; then
  OLLAMA_VER=$(ollama --version 2>/dev/null | head -1 || echo "unknown")
  pass "Ollama: already installed — $OLLAMA_VER"
  if systemctl is-active --quiet ollama 2>/dev/null; then
    info "Ollama service: running"
    MODELS=$(curl -sf http://localhost:11434/api/tags 2>/dev/null | \
      python3 -c "import sys,json; d=json.load(sys.stdin); print(', '.join(m['name'] for m in d.get('models',[])))" \
      2>/dev/null || echo "unable to list")
    info "Loaded models: ${MODELS:-none}"
  else
    info "Ollama service: not running"
  fi
else
  info "Ollama: not installed — will be installed from bundle"
fi

# ─── Check: Podman/Docker note ───────────────────────────────────────────────
header "Container Runtime (informational)"
if command -v podman >/dev/null 2>&1; then
  info "Podman available: $(podman --version 2>/dev/null | head -1) — useful for EL10 compat testing"
elif command -v docker >/dev/null 2>&1; then
  info "Docker available — not used by OpenClaw but noted"
else
  info "No container runtime found — not required for OpenClaw"
fi

# ─── Check: SELinux ─────────────────────────────────────────────────────────
header "SELinux"
if command -v sestatus >/dev/null 2>&1; then
  SELINUX_STATUS=$(sestatus 2>/dev/null | grep "SELinux status" | awk '{print $3}')
  SELINUX_MODE=$(sestatus 2>/dev/null | grep "Current mode" | awk '{print $3}')
  if [[ "$SELINUX_MODE" == "enforcing" ]]; then
    warn "SELinux: enforcing — may block services; see docs/SECURITY.md for policy notes"
  elif [[ "$SELINUX_MODE" == "permissive" ]]; then
    pass "SELinux: permissive (acceptable; consider enforcing after stable deployment)"
  else
    info "SELinux: ${SELINUX_STATUS:-unknown}"
  fi
else
  info "SELinux: sestatus not available"
fi

# ─── Check: Firewall ─────────────────────────────────────────────────────────
header "Firewall"
if systemctl is-active --quiet firewalld 2>/dev/null; then
  pass "firewalld: running"
elif systemctl is-enabled --quiet firewalld 2>/dev/null; then
  warn "firewalld: enabled but not running — installer will start it"
else
  info "firewalld: not enabled — installer will enable and start it"
fi

# ─── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════"
if [[ "$CRITICAL_FAILURES" -eq 0 ]]; then
  echo -e " ${GRN}All critical checks passed.${RST} Proceed with:"
  echo "   sudo bash 01-prepare-bundle.sh   (on internet machine)"
  echo "   sudo bash 02-install.sh          (on target machine, from bundle)"
else
  echo -e " ${RED}${CRITICAL_FAILURES} critical check(s) failed.${RST}"
  echo "   Fix the issues above before running the installer."
fi
echo "═══════════════════════════════════════════════════════════════"
echo ""

exit "$CRITICAL_FAILURES"
