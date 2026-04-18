#!/usr/bin/env bash
# =============================================================================
# OpenClaw Air-Gap Bundle Preparation Script
# =============================================================================
# Run this on an INTERNET-CONNECTED Rocky Linux 9 machine.
# Produces: /tmp/openclaw-airgap-bundle.tar.gz
#
# Requirements on the prep machine:
#   - Rocky Linux 9 (or RHEL 9 / AlmaLinux 9)
#   - Root or sudo access
#   - ~15 GB free disk space (more if downloading large models)
#   - Internet access
#
# Usage:
#   sudo bash 01-prepare-bundle.sh [--model llama3.1:8b|qwen2.5:14b|llama3.3:70b]
#   Default model: qwen2.5:14b
# =============================================================================

set -euo pipefail

# ── Helpers ───────────────────────────────────────────────────────────────────
log()  { echo -e "\033[1;32m[+]\033[0m $*"; }
warn() { echo -e "\033[1;33m[!]\033[0m $*"; }
die()  { echo -e "\033[1;31m[✗]\033[0m $*" >&2; exit 1; }

# ── Help ──────────────────────────────────────────────────────────────────────
usage() {
  cat << 'USAGE'
Usage: sudo bash 01-prepare-bundle.sh [OPTIONS]

Build the OpenClaw air-gap bundle on an internet-connected machine.

Options:
  --model MODEL    LLM model to pull via Ollama (default: qwen2.5:14b)
                   Options: llama3.1:8b | qwen2.5:14b | llama3.3:70b
  --help           Show this help message and exit

Examples:
  sudo bash 01-prepare-bundle.sh
  sudo bash 01-prepare-bundle.sh --model llama3.1:8b
  sudo bash 01-prepare-bundle.sh --model llama3.3:70b

Output:
  /tmp/openclaw-airgap-bundle.tar.gz     (transfer this to the air-gapped machine)
  /tmp/openclaw-airgap-bundle.tar.gz.sha256

After completion, transfer the .tar.gz and .sha256 files to the target machine.
USAGE
  exit 0
}

# ── Configuration ─────────────────────────────────────────────────────────────
BUNDLE_DIR="/tmp/openclaw-airgap-bundle"
MODEL="qwen2.5:14b"

NODE_MAJOR="22"
MATTERMOST_EDITION="enterprise"   # or "team" for free edition
PNPM_VERSION="9"

# ── Parse arguments ───────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h)   usage ;;
    --model=*)   MODEL="${1#--model=}"; shift ;;
    --model)     MODEL="${2:-qwen2.5:14b}"; shift 2 ;;
    *)           die "Unknown argument: $1 (use --help for usage)" ;;
  esac
done

# ── Preflight ─────────────────────────────────────────────────────────────────
log "Checking prerequisites..."
[[ "$(id -u)" -eq 0 ]] || die "Run as root or with sudo."
command -v dnf    >/dev/null || die "dnf not found – need Rocky/RHEL 9."
command -v curl   >/dev/null || die "curl not found."
command -v git    >/dev/null || die "git not found (dnf install git)."
command -v tar    >/dev/null || die "tar not found."

# Verify we're on RHEL/Rocky 9
RHEL_VER=$(rpm -E '%{rhel}' 2>/dev/null || echo "0")
[[ "$RHEL_VER" -eq 9 ]] || warn "Not on RHEL/Rocky 9 – RPM deps may not match target system."

log "Bundle dir: $BUNDLE_DIR"
log "LLM model:  $MODEL"

# ── Confirm before wiping ─────────────────────────────────────────────────────
if [[ -d "$BUNDLE_DIR" ]]; then
  warn "Bundle directory already exists: $BUNDLE_DIR"
  warn "Re-running will wipe the previous bundle contents."
  read -rp "Continue and wipe previous bundle? [y/N] " _CONFIRM
  [[ "${_CONFIRM,,}" == "y" ]] || { echo "Aborted."; exit 0; }
  rm -rf "$BUNDLE_DIR"
fi
mkdir -p "$BUNDLE_DIR"/{rpms,node-packages,binaries,models,mattermost,python-wheels,configs,scripts}

# ── PHASE 1 – RPM packages ────────────────────────────────────────────────────
log "Phase 1: Downloading RPM packages..."

# Enable required repos
dnf install -y epel-release dnf-plugins-core 2>/dev/null || true
dnf install -y "https://rpms.remirepo.net/enterprise/remi-release-9.rpm" 2>/dev/null || true

# NodeSource repo for Node 22
curl -fsSL "https://rpm.nodesource.com/setup_${NODE_MAJOR}.x" | bash - 2>/dev/null || \
  dnf config-manager --add-repo \
    "https://rpm.nodesource.com/pub_${NODE_MAJOR}.x/el/9/x86_64/" 2>/dev/null || true

RPM_PKGS=(
  "nodejs"
  "git"
  "gcc"
  "gcc-c++"
  "make"
  "python3"
  "python3-pip"
  "python3-devel"
  "ffmpeg"
  "postgresql16-server"
  "postgresql16"
  "redis"
  "firewalld"
  "curl"
  "wget"
  "tar"
  "gzip"
  "unzip"
  "jq"
  "openssl"
  "ca-certificates"
  "chromium"
)

dnf download --resolve --destdir="$BUNDLE_DIR/rpms" --arch=x86_64 \
  "${RPM_PKGS[@]}" 2>/dev/null || {
  warn "Some RPM downloads failed – trying individually..."
  for pkg in "${RPM_PKGS[@]}"; do
    dnf download --resolve --destdir="$BUNDLE_DIR/rpms" "$pkg" 2>/dev/null \
      || warn "  Skipping $pkg (not available)"
  done
}

# Build local repo metadata
dnf install -y createrepo_c 2>/dev/null || true
createrepo_c "$BUNDLE_DIR/rpms"
log "RPM phase complete: $(ls "$BUNDLE_DIR/rpms"/*.rpm 2>/dev/null | wc -l) packages"

# ── PHASE 2 – Node.js packages ────────────────────────────────────────────────
log "Phase 2: Downloading Node.js packages..."

# Install pnpm
npm install -g pnpm@latest 2>/dev/null || true
PNPM_BIN=$(command -v pnpm || npm root -g)/../bin/pnpm

# Download pnpm standalone binary
PNPM_STANDALONE_URL="https://github.com/pnpm/pnpm/releases/latest/download/pnpm-linux-x64"
curl -fsSL "$PNPM_STANDALONE_URL" -o "$BUNDLE_DIR/binaries/pnpm" 2>/dev/null || \
  warn "pnpm standalone download failed – will use npm fallback"
chmod +x "$BUNDLE_DIR/binaries/pnpm" 2>/dev/null || true

# Verify pnpm binary is a real ELF executable, not a redirect/error page
if [[ -f "$BUNDLE_DIR/binaries/pnpm" ]]; then
  PNPM_FILE_TYPE=$(file "$BUNDLE_DIR/binaries/pnpm" 2>/dev/null || echo "unknown")
  if echo "$PNPM_FILE_TYPE" | grep -q "ELF"; then
    log "  pnpm binary verified: ELF executable"
  else
    warn "  pnpm binary does not appear to be an ELF executable (got: $PNPM_FILE_TYPE)"
    warn "  Removing bad pnpm binary – npm fallback will be used during install."
    rm -f "$BUNDLE_DIR/binaries/pnpm"
  fi
fi

# Pack OpenClaw with all dependencies
log "  Packing openclaw npm package..."
OCWORK=$(mktemp -d)
cd "$OCWORK"
npm init -y >/dev/null
npm install openclaw@latest 2>/dev/null || npm install openclaw 2>/dev/null
# Archive the full node_modules (includes all transitive deps)
tar czf "$BUNDLE_DIR/node-packages/openclaw-node_modules.tar.gz" node_modules/
# Also save package-lock for reference
cp package-lock.json "$BUNDLE_DIR/node-packages/openclaw-package-lock.json" 2>/dev/null || true
# Get version
OPENCLAW_VER=$(node -e "console.log(require('./node_modules/openclaw/package.json').version)" 2>/dev/null || echo "latest")
log "  OpenClaw version: $OPENCLAW_VER"
cd - >/dev/null
rm -rf "$OCWORK"

# Pack n8n with all dependencies
log "  Packing n8n npm package..."
N8NWORK=$(mktemp -d)
cd "$N8NWORK"
npm init -y >/dev/null
npm install n8n 2>/dev/null || warn "n8n download failed"
tar czf "$BUNDLE_DIR/node-packages/n8n-node_modules.tar.gz" node_modules/ 2>/dev/null || true
cd - >/dev/null
rm -rf "$N8NWORK"

log "Node.js phase complete."

# ── PHASE 3 – Ollama binary ───────────────────────────────────────────────────
log "Phase 3: Downloading Ollama..."

OLLAMA_RELEASE_URL="https://api.github.com/repos/ollama/ollama/releases/latest"
OLLAMA_DL_URL=$(curl -fsSL "$OLLAMA_RELEASE_URL" | \
  python3 -c "import sys,json; \
    [print(a['browser_download_url']) for r in [json.load(sys.stdin)] \
     for a in r.get('assets',[]) if 'linux-amd64' in a['name'] and a['name'].endswith('.tgz')]" \
  2>/dev/null | head -1)

if [[ -z "$OLLAMA_DL_URL" ]]; then
  warn "Could not parse Ollama release URL – trying fallback..."
  OLLAMA_DL_URL="https://github.com/ollama/ollama/releases/latest/download/ollama-linux-amd64.tgz"
fi

curl -fL "$OLLAMA_DL_URL" -o "$BUNDLE_DIR/binaries/ollama-linux-amd64.tgz" || {
  # Fallback: single static binary
  curl -fL "https://ollama.com/download/ollama-linux-amd64" \
    -o "$BUNDLE_DIR/binaries/ollama" && \
    chmod +x "$BUNDLE_DIR/binaries/ollama"
}

# Install ollama locally so we can pull the model
log "  Installing ollama locally to pull model..."
if [[ -f "$BUNDLE_DIR/binaries/ollama-linux-amd64.tgz" ]]; then
  tar xzf "$BUNDLE_DIR/binaries/ollama-linux-amd64.tgz" -C /usr/local/bin/ ollama 2>/dev/null || \
  tar xzf "$BUNDLE_DIR/binaries/ollama-linux-amd64.tgz" -C /tmp/ && \
  cp /tmp/bin/ollama /usr/local/bin/ollama 2>/dev/null || true
elif [[ -f "$BUNDLE_DIR/binaries/ollama" ]]; then
  cp "$BUNDLE_DIR/binaries/ollama" /usr/local/bin/ollama
fi
chmod +x /usr/local/bin/ollama 2>/dev/null || true

# ── PHASE 4 – Ollama model ────────────────────────────────────────────────────
log "Phase 4: Pulling Ollama model '$MODEL' (this takes a while)..."
warn "  Model sizes: llama3.1:8b ~5GB | qwen2.5:14b ~9GB | llama3.3:70b ~43GB"

# Start ollama serve in background
OLLAMA_HOME="$BUNDLE_DIR/.ollama-prep"
mkdir -p "$OLLAMA_HOME"
OLLAMA_MODELS="$OLLAMA_HOME/models" OLLAMA_HOST="127.0.0.1:11435" \
  ollama serve >/tmp/ollama-prep.log 2>&1 &
OLLAMA_PID=$!
sleep 3

OLLAMA_HOST="http://127.0.0.1:11435" ollama pull "$MODEL" || {
  warn "Pull failed via local server – downloading GGUF directly..."
  # Try downloading quantized GGUF from HuggingFace as fallback
  MODEL_SLUG="${MODEL//:/-}"
  warn "  Manually download the model GGUF and place in bundle/models/ then run:"
  warn "  ollama create $MODEL -f Modelfile"
}

kill $OLLAMA_PID 2>/dev/null || true

# Validate model files were actually pulled
if ! find "$OLLAMA_HOME/models" -type f 2>/dev/null | grep -q .; then
  die "Model pull failed — no model files in $OLLAMA_HOME/models. Re-run with internet."
fi
log "  Model verified: $(find "$OLLAMA_HOME/models" -type f | wc -l) files"

# Copy model files to bundle
if [[ -d "$OLLAMA_HOME/models" ]]; then
  log "  Archiving model files..."
  tar czf "$BUNDLE_DIR/models/ollama-models.tar.gz" -C "$OLLAMA_HOME" models/
  log "  Model archive: $(du -sh "$BUNDLE_DIR/models/ollama-models.tar.gz" | cut -f1)"
else
  warn "  No model files found – you must manually add the model to the target system."
fi
rm -rf "$OLLAMA_HOME"

# ── PHASE 5 – Mattermost ──────────────────────────────────────────────────────
log "Phase 5: Downloading Mattermost..."

MM_RELEASE_URL="https://api.github.com/repos/mattermost/mattermost-server/releases/latest"
MM_VERSION=$(curl -fsSL "$MM_RELEASE_URL" | python3 -c \
  "import sys,json; print(json.load(sys.stdin)['tag_name'].lstrip('v'))" 2>/dev/null || echo "10.6.0")

MM_ARCH="linux-amd64"
MM_URL="https://releases.mattermost.com/${MM_VERSION}/mattermost-${MM_VERSION}-${MM_ARCH}.tar.gz"
curl -fL "$MM_URL" -o "$BUNDLE_DIR/mattermost/mattermost-${MM_VERSION}-${MM_ARCH}.tar.gz" || {
  warn "Mattermost download failed – check the releases page manually:"
  warn "  https://mattermost.com/deploy/"
}

# ── PHASE 6 – Python packages (Whisper) ──────────────────────────────────────
log "Phase 6: Downloading Python wheels (faster-whisper)..."

pip3 download \
  faster-whisper \
  numpy \
  torch \
  torchaudio \
  --only-binary=:all: \
  --platform=manylinux_2_28_x86_64 \
  --python-version=311 \
  -d "$BUNDLE_DIR/python-wheels/" 2>/dev/null || \
pip3 download \
  faster-whisper \
  numpy \
  -d "$BUNDLE_DIR/python-wheels/" 2>/dev/null || \
  warn "Some Python wheel downloads failed"

# Download Whisper model (base.en ~150MB, or medium ~1.5GB)
log "  Downloading Whisper 'base.en' model (tiny, fast, English-only)..."
WHISPER_MODEL_DIR="$BUNDLE_DIR/models/whisper"
mkdir -p "$WHISPER_MODEL_DIR"
python3 -c "
from faster_whisper import WhisperModel
import shutil, os
# This downloads the model to HuggingFace cache
m = WhisperModel('base.en', device='cpu', download_root='/tmp/whisper-dl')
src = '/tmp/whisper-dl'
if os.path.exists(src):
    for root, dirs, files in os.walk(src):
        for f in files:
            shutil.copy(os.path.join(root, f), '${WHISPER_MODEL_DIR}/')
print('Whisper model cached.')
" 2>/dev/null || warn "Whisper model pre-download failed – it will download on first use."

# ── PHASE 7 – Mission Control dashboard ───────────────────────────────────────
log "Phase 7: Downloading Mission Control dashboard..."

MC_URL="https://github.com/abhi1693/openclaw-mission-control/archive/refs/heads/main.tar.gz"
curl -fL "$MC_URL" -o "$BUNDLE_DIR/node-packages/openclaw-mission-control.tar.gz" || \
  warn "Mission Control download failed"

warn "NOTE: Verify Mission Control source has no outbound connections before production use."

# Pre-build if possible
if [[ -f "$BUNDLE_DIR/node-packages/openclaw-mission-control.tar.gz" ]]; then
  MCWORK=$(mktemp -d)
  tar xzf "$BUNDLE_DIR/node-packages/openclaw-mission-control.tar.gz" -C "$MCWORK"
  cd "$MCWORK"/openclaw-mission-control-main 2>/dev/null || cd "$MCWORK"/*
  npm install 2>/dev/null && npm run build 2>/dev/null || true
  tar czf "$BUNDLE_DIR/node-packages/openclaw-mission-control-built.tar.gz" . 2>/dev/null || true
  cd - >/dev/null
  rm -rf "$MCWORK"
fi

# ── PHASE 8 – Copy config templates ───────────────────────────────────────────
log "Phase 8: Including config templates..."
cp -r "$(dirname "$0")/configs" "$BUNDLE_DIR/"
cp -r "$(dirname "$0")/ansible" "$BUNDLE_DIR/"

# ── PHASE 9 – Write install manifest ──────────────────────────────────────────
cat > "$BUNDLE_DIR/MANIFEST.txt" << EOF
OpenClaw Air-Gap Bundle
Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
Prep host:  $(uname -n)
OS:         $(cat /etc/redhat-release 2>/dev/null || uname -r)
OpenClaw:   ${OPENCLAW_VER}
Model:      ${MODEL}
Mattermost: ${MM_VERSION}
Node.js:    ${NODE_MAJOR}.x (NodeSource)

Contents:
  rpms/                   - RPM packages + local repo metadata
  node-packages/          - npm package archives
  binaries/               - ollama, pnpm binaries
  models/                 - Ollama model files + Whisper model
  mattermost/             - Mattermost server archive
  python-wheels/          - Python package wheels
  configs/                - Configuration templates
  ansible/                - Ansible deployment playbook
  install.sh              - Air-gapped installer
EOF

# Copy installer into bundle for convenience
cp "$(dirname "$0")/02-install.sh" "$BUNDLE_DIR/install.sh"

# ── PHASE 10 – Final archive ───────────────────────────────────────────────────
log "Phase 10: Creating final bundle archive..."
BUNDLE_ARCHIVE="/tmp/openclaw-airgap-bundle.tar.gz"
tar czf "$BUNDLE_ARCHIVE" -C "$(dirname "$BUNDLE_DIR")" "$(basename "$BUNDLE_DIR")"
BUNDLE_SIZE=$(du -sh "$BUNDLE_ARCHIVE" | cut -f1)

# Generate SHA256 checksum
sha256sum "$BUNDLE_ARCHIVE" > "${BUNDLE_ARCHIVE}.sha256"
log "SHA256: $(cat "${BUNDLE_ARCHIVE}.sha256")"

BUNDLE_SHA256=$(awk '{print $1}' "${BUNDLE_ARCHIVE}.sha256")

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo " Bundle complete!"
echo " Archive:  $BUNDLE_ARCHIVE"
echo " SHA256:   $BUNDLE_SHA256"
echo " Size:     $BUNDLE_SIZE"
echo ""
echo " Transfer to air-gapped system:"
echo "   scp $BUNDLE_ARCHIVE ${BUNDLE_ARCHIVE}.sha256 user@airgap-host:/tmp/"
echo "   # or: copy both files to USB drive"
echo ""
echo " On air-gapped system:"
echo "   sha256sum -c /tmp/openclaw-airgap-bundle.tar.gz.sha256"
echo "   tar xzf /tmp/openclaw-airgap-bundle.tar.gz -C /tmp/"
echo "   sudo bash /tmp/openclaw-airgap-bundle/install.sh"
echo "═══════════════════════════════════════════════════════════════"
