# OpenClaw Installation Guide

> For background on what OpenClaw is and what you're building, see [README.md](../README.md).
> For architecture details, see [ARCHITECTURE.md](ARCHITECTURE.md).

## Prerequisites

**Hardware (minimum):**
- CPU: x86_64, 4-core+
- RAM: 16 GB (32 GB recommended for qwen2.5:14b)
- Disk: 60 GB free (100 GB+ recommended)

**OS:** Rocky Linux 9 (or RHEL 9 / AlmaLinux 9)

**Two machines required:**
1. **Prep machine** — internet-connected Rocky Linux 9 (can be a VM or laptop)
2. **Target machine** — the air-gapped server where OpenClaw will run

---

## Phase 1: Prep Machine (Internet-Connected)

### 1.1 — Validate prerequisites

```bash
sudo bash 00-validate.sh
```

Fix any `[FAIL]` items before proceeding.

### 1.2 — Install git and clone the repo

```bash
sudo dnf install -y git curl
# Copy this directory to the prep machine (USB, SCP, etc.)
```

### 1.3 — Build the bundle

```bash
sudo bash 01-prepare-bundle.sh --model qwen2.5:14b
```

Model options (pick based on your target machine's RAM):
| Model | RAM | Notes |
|-------|-----|-------|
| `llama3.1:8b` | 10 GB | Fast, good quality |
| `qwen2.5:14b` | 18 GB | **Recommended default** |
| `llama3.3:70b` | 48 GB | Best quality, needs strong hardware |

Expected time: 30–90 minutes depending on internet speed.

Output files:
```
/tmp/openclaw-airgap-bundle.tar.gz
/tmp/openclaw-airgap-bundle.tar.gz.sha256
```

### 1.4 — Record the SHA256

```bash
cat /tmp/openclaw-airgap-bundle.tar.gz.sha256
```

Write this down or save it — you will verify it on the target machine.

### 1.5 — Transfer the bundle

**Via SCP:**
```bash
scp /tmp/openclaw-airgap-bundle.tar.gz \
    /tmp/openclaw-airgap-bundle.tar.gz.sha256 \
    user@target-host:/tmp/
```

**Via USB drive:**
```bash
cp /tmp/openclaw-airgap-bundle.tar.gz /media/usb/
cp /tmp/openclaw-airgap-bundle.tar.gz.sha256 /media/usb/
sync
```

---

## Phase 2: Target Machine (Air-Gapped)

### 2.1 — Receive the bundle

From USB:
```bash
cp /media/usb/openclaw-airgap-bundle.tar.gz /tmp/
cp /media/usb/openclaw-airgap-bundle.tar.gz.sha256 /tmp/
```

### 2.2 — Verify integrity

```bash
sha256sum -c /tmp/openclaw-airgap-bundle.tar.gz.sha256
# Expected output: openclaw-airgap-bundle.tar.gz: OK
```

If the hash does not match, the file is corrupted. Re-transfer.

### 2.3 — Extract the bundle

```bash
sudo tar xzf /tmp/openclaw-airgap-bundle.tar.gz -C /tmp/
ls /tmp/openclaw-airgap-bundle/
# Should show: MANIFEST.txt install.sh rpms/ node-packages/ binaries/ models/ etc.
```

### 2.4 — Validate target machine prerequisites

```bash
sudo bash /tmp/openclaw-airgap-bundle/00-validate.sh
```

This will warn if the internet is not reachable (expected on air-gapped machines) but check all other requirements.

### 2.5 — Run the installer

```bash
# Defaults: user=openclaw, workspace=/opt/openclaw/workspace, hostname=localhost
sudo bash /tmp/openclaw-airgap-bundle/install.sh

# With your settings:
sudo bash /tmp/openclaw-airgap-bundle/install.sh \
  --user openclaw \
  --workspace /opt/openclaw/workspace \
  --hostname 192.168.10.50
```

The installer will:
1. Ask for confirmation
2. Install all RPM packages from the local bundle repo
3. Extract and configure OpenClaw, Ollama, Mattermost, n8n
4. Initialize PostgreSQL and create the Mattermost database
5. Install faster-whisper for voice transcription
6. Deploy all systemd services and start them with health checks
7. Apply firewall rules
8. Generate a random n8n admin password (saved to `/etc/openclaw/n8n.env`)

Total time: 10–25 minutes.

**Use `--force` to reinstall:** If the installer fails partway through and you need to re-run it, pass `--force` to skip idempotency checks and reinstall everything:
```bash
sudo bash /tmp/openclaw-airgap-bundle/install.sh --force
```

---

## Phase 3: Post-Install Configuration

### 3.1 — Set up Mattermost

1. Open `http://<SERVER_IP>:8065` in a browser
2. Create your admin account
3. Create a team (e.g., `openclaw`)
4. Go to **Main Menu → Integrations → Bot Accounts**
5. Click **Add Bot Account**:
   - Username: `openclaw-agent`
   - Display Name: `OpenClaw Agent`
   - Role: `System Administrator`
6. Click **Create Bot Account** and copy the token (shown only once)

### 3.2 — Connect OpenClaw to Mattermost

```bash
sudo openclaw-configure-mattermost <PASTE_BOT_TOKEN_HERE>
```

### 3.3 — Run the identity wizard

```bash
sudo bash /tmp/openclaw-airgap-bundle/03-configure-identity.sh
```

This walks you through setting the agent's name, your user profile, timezone, working hours, and enabling background heartbeat tasks.

### 3.4 — Add the bot to Mattermost channels

In Mattermost:
1. Create channels: `general`, `tasks`, `briefings`, `system`
2. In each channel: click channel name → **Add Members** → add `openclaw-agent`

### 3.5 — Pair your account for DMs

In Mattermost, open a DM with `openclaw-agent` and type `/pair`.

---

## Phase 4: Verification

```bash
bash /tmp/openclaw-airgap-bundle/04-health-check.sh
```

Or manually:
```bash
# Services
systemctl status openclaw ollama mattermost n8n postgresql-16

# Endpoints
curl http://localhost:11434/api/tags         # Ollama — should list models
curl http://localhost:8065/api/v4/system/ping  # Mattermost
curl http://localhost:5678/healthz           # n8n
curl http://localhost:18789/health           # OpenClaw

# Test agent
openclaw agent --message "Hello, are you there?"
```

**In Mattermost:**
```
@openclaw-agent hello, are you there?
```

The agent should respond within 10–60 seconds (first response may be slower — model loading).

---

## Troubleshooting

See [TROUBLESHOOT.md](TROUBLESHOOT.md) for common issues and fixes.

**Quick checks:**
```bash
# View recent errors
journalctl -u openclaw -n 50 --no-pager
journalctl -u ollama   -n 20 --no-pager

# n8n password (if you forgot it)
cat /etc/openclaw/n8n.env

# Mattermost DB password
cat /root/.mattermost-db-creds
```
