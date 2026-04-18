# OpenClaw Troubleshooting Guide

## Quick Diagnostics

Run the health check first:
```bash
bash 04-health-check.sh --verbose
```

Or check all service status at once:
```bash
systemctl status openclaw ollama mattermost n8n postgresql-16
journalctl -u openclaw -u ollama -u mattermost -u n8n -n 30 --no-pager
```

---

## Service Won't Start

### OpenClaw won't start

```bash
# Check detailed status:
systemctl status openclaw
journalctl -u openclaw -n 50 --no-pager

# Common causes:
# 1. Ollama not ready yet — OpenClaw depends on Ollama
systemctl status ollama
curl http://localhost:11434/api/tags

# 2. Config file has invalid JSON:
python3 -c "
import json, re
with open('/opt/openclaw/.openclaw/openclaw.json') as f:
    content = re.sub(r'//[^\n]*', '', f.read())
json.loads(content)
print('Config OK')
"

# 3. Bot token placeholder still in config:
grep 'PASTE_BOT_TOKEN' /opt/openclaw/.openclaw/openclaw.json

# 4. Workspace directory permissions:
ls -la /opt/openclaw/workspace/
# Should be owned by the openclaw user

# Fix permissions:
chown -R openclaw:openclaw /opt/openclaw/
```

### Ollama won't start

```bash
journalctl -u ollama -n 50 --no-pager

# Common cause: model directory permissions
ls -la /opt/ollama/
chown -R ollama:ollama /opt/ollama/

# Check if port is already in use:
ss -tlnp | grep 11434

# Check model files exist:
find /opt/ollama/models/ -type f | head -10
# If empty: models weren't extracted during install
tar xzf /tmp/openclaw-airgap-bundle/models/ollama-models.tar.gz -C /opt/ollama/
chown -R ollama:ollama /opt/ollama/
systemctl restart ollama
```

### Mattermost won't start

```bash
journalctl -u mattermost -n 50 --no-pager

# Common cause 1: PostgreSQL not ready yet
systemctl status postgresql-16
pg_isready

# Common cause 2: Config file has wrong DB password
cat /root/.mattermost-db-creds
# Compare DB_PASS with what's in /opt/mattermost/config/config.json
python3 -c "import json; cfg=json.load(open('/opt/mattermost/config/config.json')); print(cfg['SqlSettings']['DataSource'])"

# Common cause 3: Binary not executable or wrong path
ls -la /opt/mattermost/bin/mattermost
file /opt/mattermost/bin/mattermost

# Fix:
chmod +x /opt/mattermost/bin/mattermost
chown -R mattermost:mattermost /opt/mattermost/
systemctl restart mattermost
```

### n8n won't start

```bash
journalctl -u n8n -n 50 --no-pager

# Common cause 1: Missing env file
ls -la /etc/openclaw/n8n.env
# If missing:
N8N_PASS=$(openssl rand -base64 24 | tr -d '/+=')
echo "N8N_BASIC_AUTH_PASSWORD=${N8N_PASS}" > /etc/openclaw/n8n.env
chmod 600 /etc/openclaw/n8n.env
systemctl restart n8n

# Common cause 2: n8n binary wrapper broken
cat /usr/local/bin/n8n
node /opt/n8n-modules/node_modules/.bin/n8n --version
```

---

## Mattermost Can't Connect to PostgreSQL

```bash
# Test the connection manually:
sudo -u mattermost psql \
  "postgres://mmuser:$(grep DB_PASS /root/.mattermost-db-creds | cut -d= -f2)@localhost:5432/mattermost" \
  -c '\l'

# If connection refused:
systemctl status postgresql-16
pg_isready

# If authentication failed:
# Verify pg_hba.conf allows mmuser:
grep mmuser /var/lib/pgsql/16/data/pg_hba.conf
# If missing, add:
echo "host    mattermost      mmuser          127.0.0.1/32            md5" >> /var/lib/pgsql/16/data/pg_hba.conf
systemctl reload postgresql-16

# Reset mmuser password if lost:
NEW_PASS=$(openssl rand -base64 24 | tr -d '/+=')
sudo -u postgres psql -c "ALTER USER mmuser WITH PASSWORD '${NEW_PASS}';"
# Update /root/.mattermost-db-creds and /opt/mattermost/config/config.json
```

---

## Ollama Not Responding / Model Not Loaded

```bash
# Is Ollama running?
systemctl status ollama

# Is it listening?
curl http://localhost:11434/api/tags

# What models are loaded?
curl -s http://localhost:11434/api/tags | python3 -c "
import sys, json
data = json.load(sys.stdin)
for m in data.get('models', []):
    print(m['name'], m.get('size', ''))
"

# If no models:
# The model archive may not have been extracted. Check:
ls /opt/ollama/models/

# Re-extract:
tar xzf /tmp/openclaw-airgap-bundle/models/ollama-models.tar.gz -C /opt/ollama/
chown -R ollama:ollama /opt/ollama/
systemctl restart ollama
sleep 5
curl http://localhost:11434/api/tags

# Test inference:
curl http://localhost:11434/api/generate \
  -d '{"model":"qwen2.5:14b","prompt":"Say hello.","stream":false}' | python3 -c "
import sys, json
print(json.load(sys.stdin)['response'])
"
```

---

## OpenClaw Can't Reach Mattermost (Bot Token Issues)

```bash
# Check if Mattermost is responding:
curl http://localhost:8065/api/v4/system/ping

# Check the bot token in config:
python3 << 'EOF'
import json, re
with open('/opt/openclaw/.openclaw/openclaw.json') as f:
    content = re.sub(r'//[^\n]*', '', f.read())
cfg = json.loads(content)
mm = cfg.get('channels', {}).get('mattermost', {})
print("enabled:", mm.get('enabled'))
print("token:", mm.get('botToken', 'NOT SET')[:8] + '...' if len(mm.get('botToken', '')) > 8 else 'NOT SET')
print("baseUrl:", mm.get('baseUrl'))
EOF

# If token is 'PASTE_BOT_TOKEN_HERE' or empty:
sudo openclaw-configure-mattermost YOUR_BOT_TOKEN_HERE

# Test the token manually:
TOKEN=$(python3 -c "
import json, re
with open('/opt/openclaw/.openclaw/openclaw.json') as f:
    content = re.sub(r'//[^\n]*', '', f.read())
print(json.loads(content)['channels']['mattermost']['botToken'])
")
curl -H "Authorization: Bearer $TOKEN" http://localhost:8065/api/v4/users/me
# Should return bot user JSON
```

---

## n8n Login Fails

```bash
# Get the current password:
cat /etc/openclaw/n8n.env
# Output: N8N_BASIC_AUTH_PASSWORD=xxxxx

# If the file is missing or corrupted, regenerate:
NEW_PASS=$(openssl rand -base64 24 | tr -d '/+=')
cat > /etc/openclaw/n8n.env << EOF
N8N_BASIC_AUTH_PASSWORD=${NEW_PASS}
EOF
chmod 600 /etc/openclaw/n8n.env
systemctl restart n8n
echo "New n8n password: $NEW_PASS"
```

---

## Voice Transcription Fails

```bash
# Test faster-whisper installation:
python3 -c "import faster_whisper; print('faster-whisper OK')"

# If ImportError:
pip3 install --no-index --find-links=/tmp/openclaw-airgap-bundle/python-wheels/ faster-whisper

# Test transcription directly:
openclaw-transcribe /path/to/test.wav

# If model not found:
ls /opt/openclaw/whisper-models/
# If empty, copy from bundle:
cp -r /tmp/openclaw-airgap-bundle/models/whisper/* /opt/openclaw/whisper-models/

# If no wav test file, record 5 seconds:
arecord -f cd -t wav -d 5 /tmp/test.wav 2>/dev/null || \
  ffmpeg -f lavfi -i "sine=frequency=440:duration=2" /tmp/test.wav -y 2>/dev/null
openclaw-transcribe /tmp/test.wav
```

---

## Bundle Too Large / Disk Space Issues

```bash
# Check what's using space in the bundle:
du -sh /tmp/openclaw-airgap-bundle/*/

# Common culprits:
# models/   — Ollama model (9-43 GB)
# python-wheels/ — torch wheels if GPU selected

# Free up space on target:
df -h
# If /tmp is full, move bundle to /opt or another partition:
mv /tmp/openclaw-airgap-bundle /opt/
cd /opt/openclaw-airgap-bundle
sudo bash install.sh

# Remove bundle after successful install:
rm -rf /opt/openclaw-airgap-bundle
rm -f /tmp/openclaw-airgap-bundle.tar.gz
```

---

## Re-running the Installer After Failure

If the install fails partway through:

```bash
# Use --force to skip idempotency checks and reinstall everything:
sudo bash /tmp/openclaw-airgap-bundle/install.sh --force

# Or re-run just specific steps by editing the script and commenting out completed phases.

# Common partial-install fixes:
# - If RPMs installed but Node.js missing: check the NodeSource repo was added
# - If OpenClaw extracted but config wrong: fix openclaw.json manually, restart
# - If PostgreSQL initdb failed: check /var/lib/pgsql/16/data/ permissions
```

---

## Updating Individual Components

### Update Mattermost only

```bash
# Download new version (on prep machine with internet):
MM_VER="10.7.0"  # check mattermost.com for latest
curl -fL "https://releases.mattermost.com/${MM_VER}/mattermost-${MM_VER}-linux-amd64.tar.gz" \
  -o mattermost-new.tar.gz

# Transfer to air-gapped machine, then:
systemctl stop mattermost
cp -r /opt/mattermost /opt/mattermost.bak  # backup
tar xzf mattermost-new.tar.gz -C /opt/mattermost --strip-components=1
# Do NOT overwrite config.json during extraction:
cp /opt/mattermost.bak/config/config.json /opt/mattermost/config/
chown -R mattermost:mattermost /opt/mattermost/
systemctl start mattermost
```

### Update Ollama only

```bash
# On prep machine:
curl -fL https://ollama.com/download/ollama-linux-amd64 -o ollama-new
# Transfer, then:
systemctl stop ollama
install -m 755 ollama-new /usr/local/bin/ollama
systemctl start ollama
```

### Pull a new LLM model

```bash
# On a machine with internet access (not necessarily the target):
OLLAMA_MODELS=/tmp/new-models ollama serve &
OLLAMA_HOST=http://localhost:11434 ollama pull llama3.3:70b
tar czf llama3-models.tar.gz -C /tmp/new-models models/
# Transfer tar.gz to air-gapped machine, then:
tar xzf llama3-models.tar.gz -C /opt/ollama/
chown -R ollama:ollama /opt/ollama/
# Update config:
sudo openclaw-configure-model ollama/llama3.3:70b
systemctl restart openclaw
```

---

## Heartbeat Not Running

```bash
# Verify openclaw is running:
systemctl status openclaw

# Check heartbeat config:
cat /opt/openclaw/workspace/HEARTBEAT.md

# Manually trigger a heartbeat:
curl -X POST http://localhost:18789/api/agent/heartbeat

# Check heartbeat logs:
journalctl -u openclaw -n 50 --no-pager | grep -i heartbeat
tail -f /var/log/openclaw/gateway.log | grep heartbeat
```

---

## Model Gives Poor Responses

Possible causes:

1. **Wrong model for your hardware** — if you have < 16 GB RAM and used `qwen2.5:14b`, it will swap and be very slow. Switch to `llama3.1:8b`.

2. **Context too long** — the heartbeat `lightContext: true` setting helps with this.

3. **Model genuinely needs to be larger** — pull a 32b or 70b model if you have the RAM/GPU.

```bash
# Check current model being used:
curl -s http://localhost:18789/health | python3 -c "import sys,json; print(json.load(sys.stdin))"

# Check RAM usage while Ollama is loaded:
free -h
ollama ps  # shows active models
```
