# OpenClaw — Air-Gapped Installation Guide
### Rocky Linux 9 · Local LLM · No Internet Required

---

## What You're Building

An autonomous AI agent (OpenClaw) that:

- Runs 24/7 on a Rocky Linux 9 server
- Answers you via **Mattermost** (self-hosted Discord/Telegram replacement)
- Uses a **local LLM via Ollama** — zero cloud calls, zero data leaves the network
- Has **persistent memory** in an Obsidian-compatible markdown vault
- Runs a **heartbeat** every 30 minutes, monitoring tasks and surfacing what needs attention
- Executes **automated workflows** via n8n (self-hosted Zapier replacement)
- Transcribes **voice memos** with faster-whisper (fully offline)
- Has a **Mission Control** dashboard for monitoring

```
┌─────────────────────────────────────────────────────────────┐
│                  Air-Gapped Network                         │
│                                                             │
│   ┌─────────────┐     ┌──────────────────────────────────┐  │
│   │ Your Client │     │     OpenClaw Server (Rocky 9)    │  │
│   │  (browser / │────▶│  ┌─────────┐  ┌──────────────┐  │  │
│   │  Mattermost │     │  │Mattermost│  │  OpenClaw    │  │  │
│   │   desktop)  │     │  │  :8065  │  │  Gateway     │  │  │
│   └─────────────┘     │  └────┬────┘  │  :18789      │  │  │
│                        │       │       └──────┬───────┘  │  │
│   ┌─────────────┐     │       ▼              ▼           │  │
│   │  Obsidian   │     │  ┌─────────┐  ┌──────────────┐  │  │
│   │  (memory    │────▶│  │  n8n    │  │   Ollama     │  │  │
│   │   graph)    │     │  │  :5678  │  │  :11434      │  │  │
│   └─────────────┘     │  └─────────┘  │  (LLM model) │  │  │
│                        │               └──────────────┘  │  │
│                        │  ┌─────────────────────────────┐ │  │
│                        │  │  Mission Control  :3001     │ │  │
│                        │  └─────────────────────────────┘ │  │
│                        └──────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

---

## Hardware Requirements

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| CPU | 4-core x86_64 | 8-core+ |
| RAM | 16 GB | 32–64 GB |
| Storage | 60 GB free | 200 GB SSD |
| GPU | None (CPU-only) | NVIDIA 16GB+ VRAM |
| OS | Rocky Linux 9 | Rocky Linux 9 |

**Model vs. RAM guide:**

| Model | RAM Required | Quality |
|-------|-------------|---------|
| `llama3.1:8b` | 10 GB | Good for simple tasks |
| `qwen2.5:14b` | 18 GB | **Recommended default** |
| `qwen2.5:32b` | 24 GB (GPU) | High quality, needs GPU |
| `llama3.3:70b` | 48 GB | Best quality, needs beefy GPU |

---

## Files in This Package

```
openclaw-airgap/
├── README.md                ← You are here
├── 01-prepare-bundle.sh     ← Run on internet machine
├── 02-install.sh            ← Run on air-gapped machine
├── configs/
│   ├── openclaw.json        ← Main OpenClaw config template
│   ├── HEARTBEAT.md         ← Heartbeat task checklist
│   ├── identity/
│   │   ├── SOUL.md          ← Agent personality & values
│   │   ├── AGENTS.md        ← Operational rules / SOP
│   │   ├── TOOLS.md         ← Available capabilities
│   │   ├── user.md          ← About you (fill this in)
│   │   └── memory.md        ← Permanent facts
│   └── systemd/
│       ├── openclaw.service
│       ├── ollama.service
│       ├── mattermost.service
│       └── n8n.service
└── ansible/
    └── deploy.yml           ← Automate multi-node deployment
```

---

## PHASE 1 — Build the Bundle (Internet Machine)

> Do this on any Rocky Linux 9 machine that has internet access.
> Typically a laptop, a VM, or a temporary cloud instance.

### 1.1 — Prerequisites on the internet machine

```bash
sudo dnf install -y git curl wget createrepo_c python3-pip nodejs npm
sudo npm install -g pnpm
```

### 1.2 — Clone this package to the internet machine

```bash
# Option A: copy this directory to the internet machine via USB
# Option B: if you have git access:
# git clone <your-internal-repo>/openclaw-airgap
```

### 1.3 — Run the bundle prep script

Pick your model based on the hardware table above.

```bash
cd /path/to/openclaw-airgap
sudo bash 01-prepare-bundle.sh --model qwen2.5:14b
```

This will:
1. Download all RPMs (Node.js, PostgreSQL, Python tools, ffmpeg, etc.)
2. Download OpenClaw and all npm dependencies
3. Download Ollama binary from GitHub
4. Pull the Ollama LLM model (~9–43 GB depending on choice)
5. Download Mattermost server
6. Download n8n
7. Download faster-whisper Python wheels
8. Package everything into `/tmp/openclaw-airgap-bundle.tar.gz`

**Expected time:** 30–90 minutes depending on internet speed and model size.

### 1.4 — Transfer the bundle

```bash
# Copy to USB drive:
cp /tmp/openclaw-airgap-bundle.tar.gz /media/usb/

# Or copy to transfer server:
scp /tmp/openclaw-airgap-bundle.tar.gz transfer@jump-host:/staging/
```

**Verify integrity** (record this hash before transfer):
```bash
sha256sum /tmp/openclaw-airgap-bundle.tar.gz
```

---

## PHASE 2 — Install on the Air-Gapped Server

### 2.1 — Transfer the bundle to the target

```bash
# From USB:
cp /media/usb/openclaw-airgap-bundle.tar.gz /tmp/

# Verify hash matches what was recorded above:
sha256sum /tmp/openclaw-airgap-bundle.tar.gz
```

### 2.2 — Extract the bundle

```bash
sudo tar xzf /tmp/openclaw-airgap-bundle.tar.gz -C /tmp/
ls /tmp/openclaw-airgap-bundle/
# Should show: MANIFEST.txt install.sh rpms/ node-packages/ binaries/ models/ etc.
```

### 2.3 — Run the installer

```bash
# Minimal install (defaults: user=openclaw, hostname=localhost):
sudo bash /tmp/openclaw-airgap-bundle/install.sh

# Specify your setup:
sudo bash /tmp/openclaw-airgap-bundle/install.sh \
  --user mike \
  --workspace /opt/openclaw/workspace \
  --hostname 192.168.10.50
```

The installer will prompt once to confirm, then run all phases automatically.
Total install time: 10–20 minutes.

**Watch it run:**
```bash
# In another terminal, monitor progress:
journalctl -f
```

### 2.4 — Verify services

```bash
systemctl status ollama mattermost n8n openclaw

# Quick test that Ollama is serving the model:
curl http://localhost:11434/api/tags
# Should list your model (e.g., qwen2.5:14b)

# Quick test of OpenClaw gateway:
curl http://localhost:18789/health
```

---

## PHASE 3 — Configure Mattermost

> This replaces Discord/Telegram from the video.

### 3.1 — Create admin account

1. Open `http://<SERVER_IP>:8065` in your browser (from any machine on the LAN)
2. Click **Don't have an account? Create one**
3. Create your admin account with a strong password
4. Create a team named **openclaw** (or any name you prefer)

### 3.2 — Create the bot account

1. Top-left menu → **Integrations** → **Bot Accounts**
2. Click **Add Bot Account**
3. Fill in:
   - **Username:** `openclaw-agent`
   - **Display Name:** `OpenClaw Agent`
   - **Role:** `System Administrator`
4. Click **Create Bot Account**
5. **Copy the bot token** — you only see it once. It looks like: `abcdef1234567890abcdef12345678`

### 3.3 — Link OpenClaw to Mattermost

```bash
sudo openclaw-configure-mattermost <PASTE_BOT_TOKEN_HERE>
```

This injects the token into `/opt/openclaw/.openclaw/openclaw.json` and restarts the service.

### 3.4 — Add the bot to channels

In Mattermost:
1. Click the **+** next to **Channels** in the sidebar
2. Create channels: `general`, `tasks`, `briefings`, `system`
3. In each channel: click channel name → **Add Members** → add `openclaw-agent`

### 3.5 — Test the connection

In the `general` channel, type:
```
@openclaw-agent hello, are you there?
```

The agent should respond within 10–30 seconds (first response may be slower — model loading).

### 3.6 — Set up your user pairing (DM access)

OpenClaw uses a pairing system for DMs (security feature):

1. In Mattermost, open a Direct Message with `openclaw-agent`
2. Type: `/pair`
3. Follow the pairing instructions the bot sends back

After pairing, you can send voice memos and private messages directly.

---

## PHASE 4 — Configure Multi-Channel Workspace (like the video)

> This mirrors the "multi-agent Discord channels" section from the video.

### 4.1 — Create specialized channels

In Mattermost, create channels for each area you want the agent to manage:

```
Channel           Purpose
──────────────    ─────────────────────────────────────────
#briefings        Morning briefs, daily summaries
#tasks            Project tracking, to-do items
#system           Server health, alerts, heartbeat reports
#research         Web research results (from n8n workflows)
#content          Content ideas, drafts
#trading          Trading bot monitoring (if using Build #7)
```

For each channel, add `openclaw-agent` as a member.

### 4.2 — Create threads for projects

In any channel:
```
/thread my-project-name
Purpose: this thread tracks project XYZ
```

The agent maintains separate context per thread, just like the video shows.

---

## PHASE 5 — Fill In Your Identity Files

> These are the files that make your agent know who you are.
> Edit them at: `/opt/openclaw/workspace/`

### 5.1 — user.md (Who you are)

```bash
nano /opt/openclaw/workspace/user.md
```

Answer every section. This is the "about the boss" page — fill it in once and the agent remembers permanently. Key fields:

- Your name and how you want to be addressed
- Your role and responsibilities
- Current projects
- Tools you use
- Communication preferences
- Things the agent can decide without asking

### 5.2 — SOUL.md (Agent personality)

```bash
nano /opt/openclaw/workspace/SOUL.md
```

1. Replace `__AGENT_NAME__` with whatever you want to call your agent (e.g., "Max", "Atlas", "CAT")
2. Replace `__USER_NAME__` with your name or callsign
3. Adjust the communication style to match what you want
4. Add/remove any boundaries that don't fit your use case

### 5.3 — memory.md (Permanent facts)

```bash
nano /opt/openclaw/workspace/memory.md
```

Fill in:
- Your server's hostname and IP ranges
- Key directories and resources the agent should know about
- Standing decisions that are already made
- Anything you'd otherwise re-explain in every conversation

### 5.4 — AGENTS.md (Operational rules)

```bash
nano /opt/openclaw/workspace/AGENTS.md
```

Review the default rules and adjust:
- Change the destructive command rules to match your risk tolerance
- Add any system-specific safety rules (FreeIPA, XCP-ng, etc.)
- Define what the agent can do autonomously vs. what requires confirmation

### 5.5 — HEARTBEAT.md (Background tasks)

```bash
nano /opt/openclaw/workspace/HEARTBEAT.md
```

Uncomment and configure the tasks you actually want:
- `system-health` — checks services every hour
- `daily-log-init` — creates daily log file at 07:00
- `pending-tasks` — surfaces stalled tasks every 30 min

Add custom tasks specific to your work (see the commented examples).

### 5.6 — Restart to load identity files

```bash
sudo systemctl restart openclaw
```

In Mattermost: `@openclaw-agent tell me what you know about me`

---

## PHASE 6 — Voice Transcription

> Replaces the Whisper section from the video.

Voice transcription is already installed. To use it:

**From Mattermost:**
1. Record a voice memo on your phone
2. Send it as a file attachment to the `openclaw-agent` DM or channel
3. The agent automatically transcribes it and processes the message

**Test from command line:**
```bash
# Record a test clip (5 seconds):
arecord -f cd -t wav -d 5 /tmp/test.wav

# Transcribe it:
openclaw-transcribe /tmp/test.wav
```

**Voice model options** (trade-off: size vs. accuracy):
```bash
# Change in /usr/local/bin/openclaw-transcribe
# base.en    = fastest, English-only     (~150 MB)
# small.en   = faster, English-only      (~480 MB)
# medium.en  = balanced, English-only    (~1.5 GB)
# medium     = slower, multilingual      (~1.5 GB)
```

---

## PHASE 7 — n8n Automation (Replaces Zapier)

> This is your "agentic workflow" engine.

### 7.1 — Access n8n

Open `http://<SERVER_IP>:5678` in your browser.

Default credentials (change these immediately):
- Username: `admin`
- Password: `changeme`

Change the password:
```bash
# Edit the service file:
sudo nano /etc/systemd/system/n8n.service
# Change N8N_BASIC_AUTH_PASSWORD=changeme to something strong
sudo systemctl daemon-reload && sudo systemctl restart n8n
```

### 7.2 — Connect n8n to OpenClaw

In n8n:
1. Create a new workflow
2. Add a **Webhook** trigger node — this gives OpenClaw a URL to POST to
3. Copy the webhook URL
4. In Mattermost DM to your agent:
   ```
   I have an n8n webhook at http://localhost:5678/webhook/abc123
   When I ask you to trigger an automation, POST the task to this URL.
   ```

### 7.3 — Example: Morning Briefing Workflow

In n8n, create this workflow:
```
Schedule (07:30 daily)
    → HTTP Request (GET your internal data sources)
    → Code node (format the brief)
    → HTTP Request (POST to OpenClaw gateway → send to Mattermost #briefings)
```

The OpenClaw gateway accepts POST requests at:
`http://localhost:18789/api/agent/message`

```json
{
  "channel": "mattermost",
  "message": "Your morning brief content here"
}
```

---

## PHASE 8 — Mission Control Dashboard

```bash
# Start the dashboard:
openclaw-mc

# Access at:
http://<SERVER_IP>:3001
```

This shows:
- Active sessions and conversation history
- Which model is running
- Task board (kanban-style)
- Token usage and response times
- Service health

---

## PHASE 9 — Memory Graph with Obsidian (Optional)

> Run Obsidian on a **client machine** pointed at the server's workspace.

The workspace directory at `/opt/openclaw/workspace/` is already structured as an Obsidian vault. Every file the agent creates is a markdown file that Obsidian can visualize.

**Option A: NFS mount (recommended)**

On the server:
```bash
sudo dnf install -y nfs-utils
echo "/opt/openclaw/workspace  192.168.10.0/24(ro,sync,no_root_squash)" | sudo tee -a /etc/exports
sudo exportfs -rav
sudo systemctl enable --now nfs-server
sudo firewall-cmd --permanent --add-service=nfs && sudo firewall-cmd --reload
```

On your client workstation:
```bash
sudo mount -t nfs <SERVER_IP>:/opt/openclaw/workspace /mnt/openclaw-vault
# Then open Obsidian and point it at /mnt/openclaw-vault
```

**Option B: SSH filesystem (sshfs)**
```bash
sshfs <user>@<SERVER_IP>:/opt/openclaw/workspace /mnt/openclaw-vault
```

**Setting up Obsidian:**
1. Download Obsidian AppImage (transfer via USB from obsidian.md/download)
2. Open Obsidian → "Open folder as vault" → point to the mounted directory
3. Enable the **Graph View** plugin (built-in)
4. Open the graph: Ctrl+G

As you use your agent, the memory graph fills in automatically.

---

## PHASE 10 — Security Hardening

Run these after confirming everything works.

### 10.1 — Lock down the bot token

```bash
# Restrict permissions on the config file
sudo chmod 640 /opt/openclaw/.openclaw/openclaw.json
sudo chown openclaw:openclaw /opt/openclaw/.openclaw/openclaw.json
```

### 10.2 — Tighten OpenClaw gateway to LAN-only

Edit `/opt/openclaw/.openclaw/openclaw.json`:
```json
"gateway": {
  "host": "192.168.10.50",   // your server's LAN IP, not 0.0.0.0
  "port": 18789
}
```

### 10.3 — Create dedicated Mattermost user for each team member

Don't share the admin account. In Mattermost:
- `System Console → User Management → Users → Create User`

Each user who interacts with the bot should pair individually (`/pair` in DM).

### 10.4 — Restrict OpenClaw from accessing root-owned paths

The AGENTS.md already has this rule, but enforce it at the OS level too:
```bash
# OpenClaw runs as the 'openclaw' user — it naturally can't touch /root
# Verify:
sudo -u openclaw ls /root   # Should fail with "Permission denied"
```

### 10.5 — Disable ClawHub skill marketplace (already done)

Confirmed in `openclaw.json`:
```json
"skills": { "clawhub": { "enabled": false } }
```
Any skills must be manually placed in `/opt/openclaw/workspace/skills/`.

### 10.6 — Run OpenClaw under its own SELinux context (advanced)

```bash
# Check current SELinux status:
sestatus

# If enforcing, add a policy for openclaw if it gets blocked:
# ausearch -c 'openclaw' --raw | audit2allow -M openclaw-policy
# semodule -i openclaw-policy.pp
```

### 10.7 — Mattermost HTTPS (use if client machines support it)

```bash
# Generate self-signed cert for your internal CA:
openssl req -x509 -nodes -days 3650 \
  -newkey rsa:4096 \
  -keyout /opt/mattermost/config/server.key \
  -out    /opt/mattermost/config/server.crt \
  -subj "/CN=<SERVER_IP>/O=<ORG>/C=US"

# Update Mattermost config.json:
# "ServiceSettings": {
#   "ConnectionSecurity": "TLS",
#   "TLSCertFile": "./config/server.crt",
#   "TLSKeyFile":  "./config/server.key"
# }
```

---

## Building Skills (Offline)

> Skills are `.md` files that teach the agent a new procedure.

### Creating a skill

```bash
mkdir -p /opt/openclaw/workspace/skills/morning-brief
cat > /opt/openclaw/workspace/skills/morning-brief/SKILL.md << 'EOF'
# Morning Brief Skill

## Purpose
Produce a morning briefing from internal data sources.

## Trigger
Run every day at 07:30 via heartbeat.

## Steps
1. Read memory/$(date +%Y-%m-%d).md for any pending items from yesterday
2. Check /var/log/system-events.log for the last 24 hours (if it exists)
3. List any tasks in /opt/openclaw/workspace/tasks/ with status: pending
4. Format as a brief with sections: Pending Items | System Status | Today's Focus
5. Post to Mattermost channel #briefings

## Output format
- Start with a one-line summary
- Use bullet points
- Flag anything blocking with ⚠️
- End with "Good morning, __USER_NAME__."
EOF
```

Tell your agent about the new skill:
```
@openclaw-agent I added a new skill at workspace/skills/morning-brief/SKILL.md
Please read it, confirm you understand it, and add it to your TOOLS.md.
```

---

## Troubleshooting

### OpenClaw won't start
```bash
journalctl -u openclaw -n 50 --no-pager
# Common cause: Ollama not ready yet
systemctl status ollama
curl http://localhost:11434/api/tags
```

### Ollama is slow / running CPU-only
```bash
# Check if GPU is being used:
nvidia-smi   # (if NVIDIA GPU present)
ollama ps    # Shows active model and if GPU is active

# If GPU not detected, check driver:
lspci | grep -i nvidia
dnf install -y akmod-nvidia   # (from RPM Fusion, needs to be in bundle)
```

### Mattermost bot not responding
```bash
# Verify token in config:
cat /opt/openclaw/.openclaw/openclaw.json | python3 -m json.tool | grep botToken

# Check Mattermost is reachable from OpenClaw:
curl http://localhost:8065/api/v4/system/ping

# Check OpenClaw gateway logs:
tail -f /var/log/openclaw/gateway.log
```

### Heartbeat not running
```bash
# Verify heartbeat config:
cat /opt/openclaw/workspace/HEARTBEAT.md

# Check if openclaw service is up:
systemctl status openclaw

# Manually trigger a heartbeat:
curl -X POST http://localhost:18789/api/agent/heartbeat
```

### Model gives poor responses
The quality of responses depends heavily on the model. If you have more RAM/VRAM:
```bash
# Pull a larger model (must be done from a machine with internet, then transferred):
ollama pull llama3.3:70b

# Update config to use the new model:
sudo python3 -c "
import json
with open('/opt/openclaw/.openclaw/openclaw.json','r') as f: cfg=json.load(f)
cfg['agents']['defaults']['model']['primary'] = 'ollama/llama3.3:70b'
with open('/opt/openclaw/.openclaw/openclaw.json','w') as f: json.dump(cfg,f,indent=2)
print('Updated.')
"
sudo systemctl restart openclaw
```

---

## Ansible Deployment (Multiple Nodes)

If you're deploying to multiple machines (e.g., different departments):

```bash
# Create inventory file:
cat > inventory.ini << EOF
[openclaw_servers]
server01.internal ansible_user=root
server02.internal ansible_user=root
EOF

# Deploy:
ansible-playbook -i inventory.ini ansible/deploy.yml \
  -e "bundle_src=/tmp/openclaw-airgap-bundle" \
  -e "server_hostname={{ inventory_hostname }}" \
  -e "llm_model=qwen2.5:14b"
```

---

## Quick Reference

### Daily commands

```bash
# Check everything is running:
systemctl status openclaw ollama mattermost n8n

# View live OpenClaw logs:
journalctl -u openclaw -f

# Restart after config change:
sudo systemctl restart openclaw

# Test Ollama:
curl http://localhost:11434/api/generate \
  -d '{"model":"qwen2.5:14b","prompt":"Say hello.","stream":false}'

# Run a one-shot agent message:
openclaw agent --message "What services are you connected to?"
```

### Key file locations

| File | Location |
|------|----------|
| Main config | `/opt/openclaw/.openclaw/openclaw.json` |
| Agent soul | `/opt/openclaw/workspace/SOUL.md` |
| Agent rules | `/opt/openclaw/workspace/AGENTS.md` |
| User profile | `/opt/openclaw/workspace/user.md` |
| Memory | `/opt/openclaw/workspace/memory.md` |
| Daily logs | `/opt/openclaw/workspace/memory/YYYY-MM-DD.md` |
| Heartbeat | `/opt/openclaw/workspace/HEARTBEAT.md` |
| Skills dir | `/opt/openclaw/workspace/skills/` |
| Tasks dir | `/opt/openclaw/workspace/tasks/` |
| Gateway log | `/var/log/openclaw/gateway.log` |
| Mattermost | `http://<SERVER>:8065` |
| n8n | `http://<SERVER>:5678` |
| Dashboard | `http://<SERVER>:3001` |

---

## What the Video Showed — Air-Gapped Equivalent

| Video Feature | Air-Gapped Equivalent |
|--------------|----------------------|
| Claude API (cloud) | Ollama + local LLM |
| Discord | Mattermost (self-hosted) |
| Telegram | Mattermost mobile app |
| Zapier MCP | n8n (self-hosted) |
| AgentMail | Local SMTP + Postfix (optional) |
| ClawHub skills | Local skills in `/workspace/skills/` |
| Obsidian cloud sync | NFS or SSHFS mount |
| VPS hosting | Local Rocky Linux 9 server |
| Firecrawl browser sandbox | Playwright + Chromium (headless) |
| Nanobanana Pro (images) | ComfyUI (optional, see below) |

---

## Optional: ComfyUI for Local Image Generation

> Replaces Nanobanana Pro / Stable Diffusion APIs from the video.

This requires a GPU. Add to the bundle prep (internet machine):

```bash
# In 01-prepare-bundle.sh, add:
git clone https://github.com/comfyanonymous/ComfyUI.git "$BUNDLE_DIR/comfyui-source"
pip3 download torch torchvision --index-url https://download.pytorch.org/whl/cu124 \
  -d "$BUNDLE_DIR/python-wheels/torch-gpu/"

# Download a base model (SDXL ~6.5GB):
curl -L "https://huggingface.co/stabilityai/stable-diffusion-xl-base-1.0/resolve/main/sd_xl_base_1.0.safetensors" \
  -o "$BUNDLE_DIR/models/sd_xl_base_1.0.safetensors"
```

On the air-gapped machine:
```bash
pip3 install --no-index --find-links=/tmp/bundle/python-wheels/torch-gpu/ torch torchvision
cp -r /tmp/bundle/comfyui-source /opt/comfyui
cd /opt/comfyui && pip3 install -r requirements.txt --no-index \
  --find-links=/tmp/bundle/python-wheels/
cp /tmp/bundle/models/sd_xl_base_1.0.safetensors /opt/comfyui/models/checkpoints/
# Start: python3 main.py --listen 0.0.0.0 --port 8188
```

Create an OpenClaw skill at `/opt/openclaw/workspace/skills/image-gen/SKILL.md`
that POSTs prompts to ComfyUI's API at `http://localhost:8188`.

---

*Generated for Rocky Linux 9 air-gapped deployment.*
*OpenClaw project: https://github.com/openclaw/openclaw*
