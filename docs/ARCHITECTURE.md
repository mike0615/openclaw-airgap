# OpenClaw Architecture

## System Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                     Air-Gapped Network                              │
│                                                                     │
│  ┌─────────────┐      ┌────────────────────────────────────────┐   │
│  │ Client      │      │       OpenClaw Server (Rocky Linux 9)  │   │
│  │ (browser,   │ 8065 │  ┌──────────────┐  ┌───────────────┐  │   │
│  │  Mattermost │─────▶│  │  Mattermost  │  │   OpenClaw    │  │   │
│  │  desktop,   │      │  │   :8065      │  │   Gateway     │  │   │
│  │  mobile)    │18789 │  │  (chat UI)   │  │   :18789      │  │   │
│  │             │─────▶│  └──────┬───────┘  └───────┬───────┘  │   │
│  └─────────────┘      │         │                  │           │   │
│                        │         ▼                  ▼           │   │
│  ┌─────────────┐      │  ┌──────────────┐  ┌───────────────┐  │   │
│  │  Obsidian   │ NFS  │  │ PostgreSQL 16│  │    Ollama     │  │   │
│  │  (memory    │─────▶│  │  :5432       │  │   :11434      │  │   │
│  │   graph)    │      │  │ (MM database)│  │ (LLM engine)  │  │   │
│  └─────────────┘      │  └──────────────┘  └───────────────┘  │   │
│                        │                                         │   │
│  ┌─────────────┐      │  ┌──────────────┐  ┌───────────────┐  │   │
│  │    n8n      │      │  │     n8n      │  │  Mission Ctrl │  │   │
│  │  browser    │─────▶│  │   :5678      │  │   :3001       │  │   │
│  └─────────────┘      │  │(automation)  │  │  (dashboard)  │  │   │
│                        │  └──────────────┘  └───────────────┘  │   │
│                        │                                         │   │
│                        │  ┌─────────────────────────────────┐  │   │
│                        │  │  faster-whisper (voice/CLI)      │  │   │
│                        │  │  /usr/local/bin/openclaw-transcr │  │   │
│                        │  └─────────────────────────────────┘  │   │
│                        └────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
```

## Service Dependency Graph

```
postgresql-16
      │
      └── mattermost (requires PG)
                │
                └── openclaw (wants Mattermost, requires Ollama)
                          │
                          └── ollama (independent, starts first)

n8n (independent, calls openclaw gateway via HTTP)
```

## Component Descriptions

### OpenClaw Gateway (`:18789`)
The central AI agent runtime. Receives messages from Mattermost (via bot webhook), routes them to Ollama for LLM inference, executes skills from the workspace, and returns responses. Also runs the heartbeat scheduler — every 30 minutes it reads `HEARTBEAT.md` and executes pending tasks.

**Config:** `/opt/openclaw/.openclaw/openclaw.json`
**Logs:** `/var/log/openclaw/gateway.log`
**Binary:** `/opt/openclaw-modules/node_modules/.bin/openclaw` (via wrapper at `/usr/local/bin/openclaw`)

### Ollama (`:11434`)
Local LLM inference server. Serves the quantized model (e.g., qwen2.5:14b) over an HTTP API identical to OpenAI's format. OpenClaw sends prompts here and receives completions — no cloud involvement.

**Models:** `/opt/ollama/models/`
**Logs:** `journalctl -u ollama`
**Test:** `curl http://localhost:11434/api/tags`

### Mattermost (`:8065`)
Self-hosted team chat. Users interact with the AI agent here — in channels or DMs. OpenClaw connects as a bot account using a bot token. Mattermost also handles voice/file attachments that OpenClaw can process.

**Config:** `/opt/mattermost/config/config.json`
**Database:** PostgreSQL 16 (`mattermost` database)
**Logs:** `/var/log/openclaw/mattermost.log`

### n8n (`:5678`)
Visual workflow automation engine. Replaces cloud services like Zapier. Workflows can be triggered by schedules, webhooks, or events. Can call the OpenClaw gateway API to inject messages into the agent, or receive webhooks from the agent to trigger external actions.

**Data:** `/opt/n8n/`
**Credentials:** `/etc/openclaw/n8n.env`
**Logs:** `/var/log/openclaw/n8n.log`

### PostgreSQL 16 (`:5432`)
Relational database used exclusively by Mattermost. Not directly accessed by OpenClaw. Managed by the `mattermost` user.

**Data:** `/var/lib/pgsql/16/data/`
**Credentials:** `/root/.mattermost-db-creds`

### faster-whisper
Local speech-to-text engine using OpenAI's Whisper model. CPU-based, English-optimized (`base.en` model by default). Invoked via `openclaw-transcribe <file>` when processing voice attachments.

**Model:** `/opt/openclaw/whisper-models/`
**Binary:** `/usr/local/bin/openclaw-transcribe`

### Mission Control Dashboard (`:3001`)
Optional web dashboard for monitoring OpenClaw. Shows active sessions, conversation history, service health, and task board. Not critical for operation.

**Files:** `/opt/mission-control/`

## Data Flow: User Message to LLM Response

```
1. User sends message in Mattermost
         │
         ▼
2. Mattermost bot webhook → OpenClaw Gateway (:18789)
         │
         ▼
3. Gateway loads context:
   - SOUL.md (identity)
   - user.md (operator profile)
   - memory.md (permanent facts)
   - AGENTS.md (rules)
   - today's memory/YYYY-MM-DD.md (session log)
         │
         ▼
4. Gateway builds prompt + context → POST to Ollama (:11434)
         │
         ▼
5. Ollama runs inference (qwen2.5:14b or configured model)
   - CPU only: ~10-30s for 8b model, ~20-60s for 14b
   - GPU (if configured): ~2-10s
         │
         ▼
6. Response returned to Gateway
         │
         ▼
7. Gateway optionally executes tools/skills
   (reads/writes files, runs shell commands, calls n8n webhooks)
         │
         ▼
8. Response posted back to Mattermost channel/thread
         │
         ▼
9. Gateway logs action to memory/YYYY-MM-DD.md
```

## Air-Gap Design

### What Is Bundled (in openclaw-airgap-bundle.tar.gz)
| Category | Contents |
|----------|----------|
| RPMs | nodejs, python3, postgresql16, ffmpeg, and ~20 dependencies |
| Node packages | openclaw (+ all node_modules), n8n (+ all node_modules) |
| Binaries | ollama (static binary), pnpm (static binary) |
| LLM model | Ollama model files (compressed, ~5–43GB depending on model) |
| Mattermost | Full Mattermost server release archive |
| Python wheels | faster-whisper, numpy, torch (CPU) |
| Whisper model | base.en model files (~150MB) |
| Configs | Templates, identity files, systemd units |

### What Is NOT Bundled (by design)
- No cloud API keys
- No outbound connections from any service
- No telemetry (disabled in all service configs)
- No update checks (disabled)

### Why Air-Gap?
- Data sovereignty: all conversations, context, and model inference stay on your hardware
- Security: no exfiltration vector via LLM API calls
- Reliability: no dependency on external services or internet connectivity
- Compliance: meets requirements for classified, regulated, or sensitive environments

## Directory Layout

```
/opt/
├── openclaw/
│   ├── .openclaw/
│   │   └── openclaw.json      ← main config
│   ├── workspace/
│   │   ├── SOUL.md            ← agent personality
│   │   ├── user.md            ← operator profile
│   │   ├── memory.md          ← permanent facts
│   │   ├── AGENTS.md          ← operational rules
│   │   ├── TOOLS.md           ← available capabilities
│   │   ├── HEARTBEAT.md       ← background task list
│   │   ├── skills/            ← custom skill definitions
│   │   ├── tasks/             ← task tracking files
│   │   ├── memory/            ← daily log files (YYYY-MM-DD.md)
│   │   └── voice-inbox/       ← drop audio files here for transcription
│   ├── whisper-models/        ← Whisper model files
│   └── backups/               ← daily memory backups
├── openclaw-modules/
│   └── node_modules/          ← openclaw npm package
├── ollama/
│   └── models/                ← LLM model files
├── mattermost/
│   ├── bin/mattermost         ← server binary
│   └── config/config.json     ← Mattermost config
├── n8n/                       ← n8n data directory
├── n8n-modules/
│   └── node_modules/          ← n8n npm package
└── mission-control/           ← dashboard files

/var/log/openclaw/
├── gateway.log
├── gateway-error.log
├── mattermost.log
├── mattermost-error.log
├── n8n.log
└── n8n-error.log

/etc/openclaw/
└── n8n.env                    ← n8n credentials (600 perms)

/root/
└── .mattermost-db-creds       ← PostgreSQL credentials (600 perms)
```

## Network Ports

| Port | Service | Protocol | Bound To | Purpose |
|------|---------|----------|----------|---------|
| 18789 | OpenClaw Gateway | TCP | 127.0.0.1* | AI agent HTTP API |
| 8065 | Mattermost | TCP | 0.0.0.0 | Chat UI + bot API |
| 5678 | n8n | TCP | 0.0.0.0 | Workflow automation UI |
| 3001 | Mission Control | TCP | 0.0.0.0 | Dashboard |
| 11434 | Ollama | TCP | 127.0.0.1 | LLM inference (internal only) |
| 5432 | PostgreSQL | TCP | 127.0.0.1 | Database (internal only) |

\* Default. Change `"host"` in openclaw.json to expose to LAN (then secure with firewall rules).
