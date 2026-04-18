# OpenClaw Configuration Guide

## Identity Files

All identity files live in `/opt/openclaw/workspace/` (or your configured workspace path).
They are Markdown files read by the agent at the start of every session.

Run the interactive wizard to configure them:
```bash
sudo bash 03-configure-identity.sh
```

Or edit them directly:
```bash
nano /opt/openclaw/workspace/SOUL.md
```

After any change, restart OpenClaw:
```bash
sudo systemctl restart openclaw
```

### SOUL.md — Agent Personality

Defines who the agent is: name, core values, communication style, and hard boundaries.

Key fields to customize:
- `__AGENT_NAME__` → replace with your agent's name (e.g., `Atlas`, `MAX`, `CLAW`)
- `__USER_NAME__` → replace with your name or callsign
- Communication style section — adjust verbosity and tone
- Boundaries — add or remove rules based on your use case

Keep SOUL.md under 100 lines — it loads on every request.

### user.md — Operator Profile

Tells the agent who you are: role, projects, tools, and preferences.

Fill in every section. The more detail here, the less you repeat yourself in conversations. Key sections:
- **Identity** — name, callsign, timezone, working hours
- **Role & Responsibilities** — what you do, what decisions you make
- **Current Projects** — agent will surface relevant context automatically
- **Tools I Use** — so agent knows what commands/systems are available
- **Communication Preferences** — short/full, bullets/prose, diff/full code
- **What NOT to Bother Me With** — decisions agent can make autonomously

### memory.md — Permanent Facts

Non-expiring context: system topology, standing decisions, key paths. Unlike daily logs (which are created fresh each day), this file persists and is always loaded.

Fill in:
- Hostname, IP ranges, key DNS names
- Directories that matter (repos, data, config paths)
- Decisions already made (so agent doesn't re-debate them)
- Any recurring context you're tired of re-explaining

### AGENTS.md — Operational Rules

The SOP: security rules, task management rules, code rules, communication rules, memory management. These are the "how to behave" rules as opposed to SOUL.md's "who you are" rules.

Review the defaults and adjust:
- Security rules match your risk tolerance
- Autonomous decision thresholds
- System-specific safety constraints (FreeIPA, XCP-ng, etc.)

### TOOLS.md — Available Capabilities

Tells the agent what tools and services it has access to. Update this whenever you add a skill or integration:

```markdown
## Skills Installed
- morning-brief: produce daily briefing | invoke with: /morning-brief
- inventory-check: check XCP-ng host status | invoke with: /inventory
```

---

## HEARTBEAT.md — Background Task Configuration

The heartbeat runs every 30 minutes. Each task specifies:
- `name` — unique identifier
- `interval` — how often to run (`15m`, `1h`, `24h`, etc.)
- `runAt` — for 24h tasks, what time of day (24h format, e.g., `07:30`)
- `activeHours` — optional window when task can run
- `prompt` — the exact instructions sent to the agent

### Editing tasks

```bash
nano /opt/openclaw/workspace/HEARTBEAT.md
sudo systemctl restart openclaw
```

### Built-in tasks (enabled by default after wizard)

| Task | Interval | Purpose |
|------|----------|---------|
| `daily-log-init` | 24h at 07:00 | Creates daily log, surfaces unresolved items |
| `system-health` | 1h | Checks services, disk, RAM, failed units |
| `pending-tasks` | 30m | Surfaces stalled task files in workspace/tasks/ |
| `log-rotation-check` | 24h at 02:00 | Manages log file sizes |
| `backup-check` | 24h at 06:00 | Verifies /var/log/backup.log is current |
| `security-scan` | 24h at 03:00 | Checks failed SSH logins in /var/log/secure |
| `service-restart-alert` | 15m | Alerts if any service restarts > 3 times/day |
| `workspace-backup` | 24h at 02:30 | Backs up memory/ to /opt/openclaw/backups/ |

### Adding a custom task

```yaml
  - name: my-custom-check
    interval: 6h
    activeHours:
      start: "08:00"
      end: "18:00"
    prompt: |
      Check /var/log/my-app.log for ERROR lines in the last 6 hours.
      If found, send a DM with the count and last 5 error lines.
      Otherwise reply HEARTBEAT_OK.
```

---

## openclaw.json Key Settings

File location: `/opt/openclaw/.openclaw/openclaw.json`

Edit carefully — this is JSON5 (supports `//` comments). Use python3 to validate after edits:
```bash
python3 -c "import json,re; json.loads(re.sub(r'//[^\n]*','',open('/opt/openclaw/.openclaw/openclaw.json').read())); print('Valid JSON')"
```

### Key settings

| Setting | Path | Default | Notes |
|---------|------|---------|-------|
| LLM model | `agents.defaults.model.primary` | `ollama/qwen2.5:14b` | Change after pulling new model |
| Gateway host | `gateway.host` | `127.0.0.1` | Set to `0.0.0.0` for LAN access |
| Gateway port | `gateway.port` | `18789` | Change if port conflicts |
| Heartbeat interval | `agents.defaults.heartbeat.every` | `30m` | Min `5m` |
| Active hours | `agents.defaults.heartbeat.activeHours` | 06:00–23:00 ET | When heartbeat runs |
| Workspace path | `workspace` | `/opt/openclaw/workspace` | Set at install |
| Bot token | `channels.mattermost.botToken` | (empty) | Set via `openclaw-configure-mattermost` |
| Mattermost URL | `channels.mattermost.baseUrl` | `http://SERVER:8065` | Set at install |
| Skills directory | `skills.directory` | `WORKSPACE/skills` | Where to find skill files |

### Changing the LLM model

```bash
# 1. Pull the new model (needs Ollama running, internet on air-gap prep machine):
OLLAMA_HOST=http://localhost:11434 ollama pull llama3.3:70b

# 2. Update config:
sudo python3 << 'EOF'
import json, re
path = '/opt/openclaw/.openclaw/openclaw.json'
with open(path) as f:
    content = re.sub(r'//[^\n]*', '', f.read())
cfg = json.loads(content)
cfg['agents']['defaults']['model']['primary'] = 'ollama/llama3.3:70b'
with open(path, 'w') as f:
    json.dump(cfg, f, indent=2)
print("Updated.")
EOF

# 3. Restart:
sudo systemctl restart openclaw
```

---

## Mattermost Bot Token Setup

If you need to re-configure or update the bot token:

```bash
sudo openclaw-configure-mattermost <NEW_TOKEN>
```

This updates `openclaw.json` and restarts the service automatically.

To get a new token from Mattermost:
1. Log in as admin → System Console → Integrations → Bot Accounts
2. Find `openclaw-agent` → click to view → Token → Regenerate (or create new bot)

---

## n8n Workflow Setup

### Access n8n

1. Open `http://<SERVER_IP>:5678`
2. Username: `admin`
3. Password: `cat /etc/openclaw/n8n.env`

### Import bundled workflows

The bundle includes two example workflows in `configs/workflows/`:

**webhook-example.json** — Tests the OpenClaw webhook integration:
1. In n8n: **Workflows → Import from File**
2. Select `webhook-example.json`
3. Activate the workflow
4. Test: `curl -X POST http://localhost:5678/webhook/openclaw-test -d '{"hello":"world"}'`

**voice-transcribe-workflow.json** — Auto-transcribes audio files from voice-inbox:
1. Import from file
2. Review the workflow — it polls `/opt/openclaw/voice-inbox/` every 2 minutes
3. Activate after confirming faster-whisper is installed
4. Test: `cp /tmp/test.wav /opt/openclaw/voice-inbox/`

### Connect n8n to OpenClaw

The OpenClaw gateway accepts POST requests at `http://localhost:18789/api/agent/message`:
```json
{
  "channel": "mattermost",
  "channelName": "general",
  "message": "Your message here"
}
```

Use this in n8n HTTP Request nodes to inject messages into the agent from workflows.

---

## Voice Transcription Setup

Voice transcription is installed automatically. To use it:

**From command line:**
```bash
openclaw-transcribe /path/to/audio.wav
```

**From Mattermost:**
Attach a `.wav` or `.mp3` file to a message to the bot — it will transcribe automatically.

**Via voice-inbox (n8n workflow):**
Drop audio files into `/opt/openclaw/voice-inbox/`. The n8n workflow picks them up every 2 minutes, transcribes, and posts to Mattermost.

**Change the Whisper model:**

Edit `/usr/local/bin/openclaw-transcribe`:
```python
# Change 'base.en' to one of:
# base.en   — fastest, English-only (~150 MB)
# small.en  — fast, English-only (~480 MB)
# medium.en — balanced, English-only (~1.5 GB)
# medium    — multilingual (~1.5 GB)
# large-v3  — highest quality, all languages (~3 GB)
model = WhisperModel("medium.en", device="cpu", ...)
```

Note: larger models must be pre-downloaded during bundle prep or downloaded separately.
