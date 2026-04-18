# OpenClaw Advanced Topics

## Switching LLM Models

### Step 1: Get the new model

On a machine with internet access (the original prep machine, or a temporary VM):

```bash
# Start Ollama with a custom model directory:
OLLAMA_MODELS=/tmp/new-model-export ollama serve &
sleep 3

# Pull the desired model:
OLLAMA_HOST=http://localhost:11434 ollama pull llama3.3:70b

# Archive:
tar czf /tmp/llama3.3-70b-models.tar.gz -C /tmp/new-model-export models/
sha256sum /tmp/llama3.3-70b-models.tar.gz > /tmp/llama3.3-70b-models.tar.gz.sha256
```

### Step 2: Transfer to air-gapped machine

```bash
scp /tmp/llama3.3-70b-models.tar.gz user@airgap-host:/tmp/
```

### Step 3: Install on target

```bash
# Merge into existing Ollama models directory:
tar xzf /tmp/llama3.3-70b-models.tar.gz -C /opt/ollama/
chown -R ollama:ollama /opt/ollama/
systemctl restart ollama
sleep 5
curl http://localhost:11434/api/tags   # verify new model appears

# Update openclaw.json:
sudo python3 << 'EOF'
import json, re
path = '/opt/openclaw/.openclaw/openclaw.json'
with open(path) as f:
    content = re.sub(r'//[^\n]*', '', f.read())
cfg = json.loads(content)
cfg['agents']['defaults']['model']['primary'] = 'ollama/llama3.3:70b'
with open(path, 'w') as f:
    json.dump(cfg, f, indent=2)
print("Model updated to llama3.3:70b")
EOF

sudo systemctl restart openclaw
```

---

## Adding Custom Skills

Skills teach the agent new procedures. A skill is a directory containing a `SKILL.md` file.

### Directory structure

```
/opt/openclaw/workspace/skills/
└── my-skill/
    └── SKILL.md          ← required: skill description and steps
    └── run.sh            ← optional: executable for the skill
    └── config.yml        ← optional: skill-specific settings
```

### Example: Infrastructure status skill

```bash
mkdir -p /opt/openclaw/workspace/skills/infra-status
cat > /opt/openclaw/workspace/skills/infra-status/SKILL.md << 'EOF'
# Skill: Infrastructure Status

## Purpose
Report the current health of all monitored hosts and services.

## Trigger
Invoked manually with: `/infra-status`
Also runs as part of the daily morning briefing.

## Steps
1. Run: `systemctl status openclaw ollama mattermost n8n postgresql-16`
2. Check disk usage: `df -h | grep -v tmpfs`
3. Check CPU and memory: `top -bn1 | head -15`
4. Check last 10 lines of each service error log
5. Format as a table with status (OK/WARN/CRIT) per service

## Output format
Markdown table with columns: Service | Status | Notes
Follow with a one-line summary: "All systems nominal" or "N services need attention."

## Permissions
Read-only diagnostics only. No system changes.
EOF

chown -R openclaw:openclaw /opt/openclaw/workspace/skills/
```

Tell the agent about the new skill:
```
@openclaw-agent I added a new skill at workspace/skills/infra-status/SKILL.md
Please read it and add it to your TOOLS.md.
```

---

## ComfyUI Local Image Generation

Requires an NVIDIA GPU (16 GB+ VRAM recommended).

### On the prep machine (with internet):

```bash
# Download ComfyUI source
git clone https://github.com/comfyanonymous/ComfyUI.git /tmp/comfyui-source

# Download GPU-accelerated torch wheels
pip3 download torch torchvision \
  --index-url https://download.pytorch.org/whl/cu124 \
  -d /tmp/bundle/python-wheels/torch-gpu/

# Download SDXL base model (~6.5 GB):
curl -L "https://huggingface.co/stabilityai/stable-diffusion-xl-base-1.0/resolve/main/sd_xl_base_1.0.safetensors" \
  -o /tmp/bundle/models/sd_xl_base_1.0.safetensors

# Archive ComfyUI:
tar czf /tmp/bundle/comfyui-source.tar.gz -C /tmp comfyui-source/
```

### On the air-gapped machine:

```bash
# Install GPU torch:
pip3 install --no-index --find-links=/tmp/bundle/python-wheels/torch-gpu/ torch torchvision

# Install ComfyUI:
tar xzf /tmp/bundle/comfyui-source.tar.gz -C /opt/
mv /opt/comfyui-source /opt/comfyui

cd /opt/comfyui
pip3 install -r requirements.txt --no-index \
  --find-links=/tmp/bundle/python-wheels/

# Install model:
cp /tmp/bundle/models/sd_xl_base_1.0.safetensors /opt/comfyui/models/checkpoints/

# Create systemd service:
cat > /etc/systemd/system/comfyui.service << 'SVC'
[Unit]
Description=ComfyUI Local Image Generation
After=network.target

[Service]
Type=simple
User=openclaw
WorkingDirectory=/opt/comfyui
ExecStart=/usr/bin/python3 main.py --listen 127.0.0.1 --port 8188 --cuda-device 0
Restart=on-failure
RestartSec=10
StandardOutput=append:/var/log/openclaw/comfyui.log
StandardError=append:/var/log/openclaw/comfyui-error.log

[Install]
WantedBy=multi-user.target
SVC

systemctl daemon-reload
systemctl enable --now comfyui
```

Add a skill to use it:
```bash
mkdir -p /opt/openclaw/workspace/skills/image-gen
cat > /opt/openclaw/workspace/skills/image-gen/SKILL.md << 'EOF'
# Skill: Image Generation (ComfyUI)

## Purpose
Generate images from text prompts using the local ComfyUI server.

## Trigger
Invoked with: `/generate-image <prompt>`

## Endpoint
POST http://localhost:8188/prompt

## Steps
1. Format the prompt as a ComfyUI workflow JSON
2. POST to the ComfyUI API
3. Poll for completion
4. Return the image path to the user

## Permissions
Write access to /opt/comfyui/output/ only.
EOF
```

---

## Multi-User Mattermost Setup

### Create individual user accounts

In Mattermost Admin Console (System Console → User Management → Users):
1. Click **Create User**
2. Set username, email, and temporary password
3. Set role: Member (or System Admin for other admins)

### Per-user pairing with OpenClaw

Each user must pair with the OpenClaw bot for DM access:
1. Open a DM with `openclaw-agent`
2. Type: `/pair`
3. Follow the pairing challenge

### Channel permissions

OpenClaw responds in channels only when `@mentioned` (default policy). For private channels:
1. Add `openclaw-agent` as a member of the private channel
2. Update `AGENTS.md` if you want different behavior per channel

---

## Obsidian Vault Sync over NFS

Access the OpenClaw workspace as an Obsidian vault from any client on your LAN.

### Server setup

```bash
# Install NFS:
sudo dnf install -y nfs-utils

# Export the workspace (read-only for clients):
echo "/opt/openclaw/workspace  192.168.10.0/24(ro,sync,no_root_squash)" | \
  sudo tee -a /etc/exports

# Start NFS:
sudo systemctl enable --now nfs-server
sudo exportfs -rav

# Open firewall:
sudo firewall-cmd --permanent --add-service=nfs
sudo firewall-cmd --reload
```

### Client mount (Linux)

```bash
sudo mkdir -p /mnt/openclaw-vault
sudo mount -t nfs <SERVER_IP>:/opt/openclaw/workspace /mnt/openclaw-vault

# Make permanent:
echo "<SERVER_IP>:/opt/openclaw/workspace  /mnt/openclaw-vault  nfs  ro,defaults  0  0" | \
  sudo tee -a /etc/fstab
```

### Client mount (macOS)

```bash
sudo mkdir -p /mnt/openclaw-vault
sudo mount -t nfs -o resvport,ro <SERVER_IP>:/opt/openclaw/workspace /mnt/openclaw-vault
```

Open Obsidian → **Open folder as vault** → select `/mnt/openclaw-vault`

---

## Backup and Restore Procedure

### What to back up

| Priority | Path | Contents |
|----------|------|----------|
| Critical | `/opt/openclaw/workspace/` | Identity files, skills, tasks, memory |
| Critical | `/opt/openclaw/.openclaw/openclaw.json` | Config including bot token |
| Critical | `/root/.mattermost-db-creds` | DB credentials |
| Critical | `/etc/openclaw/n8n.env` | n8n password |
| Important | PostgreSQL database | Mattermost data |
| Optional | `/opt/mattermost/config/config.json` | Mattermost config |

### Automated backup (daily via heartbeat)

The `workspace-backup` heartbeat task creates nightly compressed backups of `memory/` to `/opt/openclaw/backups/`.

### Full system backup script

```bash
#!/usr/bin/env bash
BACKUP_ROOT="/opt/openclaw/backups"
DATE=$(date +%Y-%m-%d)
mkdir -p "$BACKUP_ROOT"

# Workspace:
tar czf "$BACKUP_ROOT/$DATE-workspace.tar.gz" /opt/openclaw/workspace/ 2>/dev/null

# Config:
tar czf "$BACKUP_ROOT/$DATE-config.tar.gz" \
  /opt/openclaw/.openclaw/ \
  /etc/openclaw/ \
  /opt/mattermost/config/ 2>/dev/null

# PostgreSQL:
sudo -u postgres pg_dump mattermost | gzip > "$BACKUP_ROOT/$DATE-mattermost-db.sql.gz"

# Keep 30 days:
find "$BACKUP_ROOT" -name "*.tar.gz" -o -name "*.sql.gz" | \
  sort | head -n -90 | xargs rm -f 2>/dev/null || true

echo "Backup complete: $BACKUP_ROOT/$DATE-*"
```

### Restore from backup

```bash
# Stop services:
systemctl stop openclaw mattermost n8n

# Restore workspace:
tar xzf /path/to/YYYY-MM-DD-workspace.tar.gz -C /

# Restore configs:
tar xzf /path/to/YYYY-MM-DD-config.tar.gz -C /

# Restore Mattermost database:
sudo -u postgres psql mattermost < <(gunzip -c /path/to/YYYY-MM-DD-mattermost-db.sql.gz)

# Restart services:
systemctl start mattermost openclaw n8n
```

---

## Enabling Mattermost HTTPS

See [SECURITY.md](SECURITY.md) for TLS setup instructions. Once enabled:

Update the Mattermost URL in openclaw.json:
```bash
sudo python3 << 'EOF'
import json, re
path = '/opt/openclaw/.openclaw/openclaw.json'
with open(path) as f:
    content = re.sub(r'//[^\n]*', '', f.read())
cfg = json.loads(content)
# Update to https:
cfg['channels']['mattermost']['baseUrl'] = cfg['channels']['mattermost']['baseUrl'].replace('http://', 'https://')
cfg['channels']['mattermost']['interactions']['callbackBaseUrl'] = \
    cfg['channels']['mattermost']['interactions']['callbackBaseUrl'].replace('http://', 'https://')
with open(path, 'w') as f:
    json.dump(cfg, f, indent=2)
print("Updated to HTTPS.")
EOF
sudo systemctl restart openclaw
```

---

## CLI Cheatsheet

### OpenClaw

```bash
openclaw --version                           # show version
openclaw agent --message "hello"             # send one-shot message
openclaw gateway --config /path/config.json  # start gateway manually
systemctl restart openclaw                   # restart service
journalctl -u openclaw -f                    # live logs
tail -f /var/log/openclaw/gateway.log        # file log
```

### Ollama

```bash
ollama list                          # list downloaded models
ollama ps                            # show active (loaded) models
ollama pull qwen2.5:14b              # pull model (needs internet)
ollama rm llama3.1:8b                # remove model
ollama run qwen2.5:14b               # interactive chat session
curl http://localhost:11434/api/tags # list via API

# One-shot generation:
curl http://localhost:11434/api/generate \
  -d '{"model":"qwen2.5:14b","prompt":"Explain NFS.","stream":false}' | \
  python3 -c "import sys,json; print(json.load(sys.stdin)['response'])"
```

### Mattermost

```bash
# Admin CLI:
/opt/mattermost/bin/mattermost user list
/opt/mattermost/bin/mattermost channel list openclaw
/opt/mattermost/bin/mattermost bot list

# Service:
systemctl restart mattermost
journalctl -u mattermost -f
```

### PostgreSQL

```bash
sudo -u postgres psql                        # interactive shell
sudo -u postgres psql -c '\l'               # list databases
sudo -u postgres psql mattermost -c '\dt'   # list Mattermost tables
pg_isready                                   # check readiness
```

### n8n

```bash
cat /etc/openclaw/n8n.env                    # get password
systemctl restart n8n
journalctl -u n8n -f

# Test webhook:
curl -X POST http://localhost:5678/webhook/openclaw-test \
  -H 'Content-Type: application/json' \
  -d '{"test": "hello"}'
```

### System diagnostics

```bash
# Full health check:
bash 04-health-check.sh --verbose

# All openclaw service status:
systemctl status openclaw ollama mattermost n8n postgresql-16

# All openclaw logs (last 50 lines each):
for svc in openclaw ollama mattermost n8n; do
  echo "=== $svc ==="; journalctl -u $svc -n 50 --no-pager; echo
done

# Disk usage:
df -h && du -sh /opt/ollama/models/ /opt/openclaw/workspace/

# RAM usage:
free -h && ollama ps
```
