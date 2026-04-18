# OpenClaw — Air-Gapped AI Agent
### Rocky Linux 9 · Local LLM · No Internet Required

A complete autonomous AI agent stack that runs entirely offline on your own hardware. Chat via self-hosted Mattermost, run a local LLM with Ollama, automate workflows with n8n, and transcribe voice memos — zero cloud calls, zero data leaves your network.

---

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                   Air-Gapped Network                         │
│                                                              │
│  ┌─────────────┐    ┌──────────────────────────────────┐    │
│  │ Your Client │    │    OpenClaw Server (Rocky 9)      │    │
│  │  (browser,  │───▶│  ┌───────────┐  ┌────────────┐  │    │
│  │  Mattermost │    │  │Mattermost │  │  OpenClaw  │  │    │
│  │  desktop)   │    │  │  :8065    │  │  :18789    │  │    │
│  └─────────────┘    │  └─────┬─────┘  └─────┬──────┘  │    │
│                      │        │               │          │    │
│  ┌─────────────┐    │        ▼               ▼          │    │
│  │  Obsidian   │    │  ┌───────────┐  ┌────────────┐  │    │
│  │  (memory    │────│  │ PostgreSQL│  │   Ollama   │  │    │
│  │   graph)    │    │  │  :5432    │  │  :11434    │  │    │
│  └─────────────┘    │  └───────────┘  │ (LLM model)│  │    │
│                      │  ┌───────────┐  └────────────┘  │    │
│                      │  │    n8n    │  ┌────────────┐  │    │
│                      │  │  :5678    │  │ whisper    │  │    │
│                      │  └───────────┘  │ (voice)    │  │    │
│                      │                 └────────────┘  │    │
│                      └──────────────────────────────────┘    │
└──────────────────────────────────────────────────────────────┘
```

---

## Quick Start

**Step 1** — On an internet-connected Rocky Linux 9 machine, build the bundle:
```bash
sudo bash 00-validate.sh                              # check prerequisites
sudo bash 01-prepare-bundle.sh --model qwen2.5:14b   # downloads everything (~9 GB)
```

**Step 2** — Transfer to the air-gapped target:
```bash
scp /tmp/openclaw-airgap-bundle.tar.gz \
    /tmp/openclaw-airgap-bundle.tar.gz.sha256 \
    user@target:/tmp/
```

**Step 3** — On the air-gapped machine, install:
```bash
sha256sum -c /tmp/openclaw-airgap-bundle.tar.gz.sha256
tar xzf /tmp/openclaw-airgap-bundle.tar.gz -C /tmp/
sudo bash /tmp/openclaw-airgap-bundle/install.sh --hostname 192.168.10.50
```

**Step 4** — Configure identity and Mattermost:
```bash
sudo bash 03-configure-identity.sh     # interactive wizard
# Then: create Mattermost admin + bot account in browser
sudo openclaw-configure-mattermost <BOT_TOKEN>
```

**Step 5** — Verify everything:
```bash
bash 04-health-check.sh
# In Mattermost: @openclaw-agent hello, are you there?
```

Full installation guide: [docs/INSTALL.md](docs/INSTALL.md)

---

## Components and Ports

| Service | Port | Purpose |
|---------|------|---------|
| OpenClaw Gateway | 18789 | AI agent HTTP API (binds to 127.0.0.1 by default) |
| Mattermost | 8065 | Self-hosted team chat (user interface) |
| n8n | 5678 | Workflow automation (schedules, webhooks) |
| Ollama | 11434 | Local LLM inference (internal only, 127.0.0.1) |
| PostgreSQL | 5432 | Database for Mattermost (internal only) |
| Mission Control | 3001 | Monitoring dashboard (optional) |

---

## Scripts

| Script | Purpose | Run On |
|--------|---------|--------|
| `00-validate.sh` | Check prerequisites before starting | Both machines |
| `01-prepare-bundle.sh` | Download and package all components | Prep machine (internet) |
| `02-install.sh` | Install OpenClaw and all services | Target machine (air-gapped) |
| `03-configure-identity.sh` | Interactive identity/personality wizard | Target machine, post-install |
| `04-health-check.sh` | Comprehensive health verification | Target machine, anytime |

---

## Requirements

**Hardware (minimum):**
| Component | Minimum | Recommended |
|-----------|---------|-------------|
| CPU | 4-core x86_64 | 8-core+ |
| RAM | 16 GB | 32–64 GB |
| Storage | 60 GB free | 200 GB SSD |
| GPU | Not required (CPU-only) | NVIDIA 16 GB+ VRAM |

**Model vs. RAM:**
| Model | RAM Required | Notes |
|-------|-------------|-------|
| `llama3.1:8b` | 10 GB | Fast, good for most tasks |
| `qwen2.5:14b` | 18 GB | **Recommended default** |
| `llama3.3:70b` | 48 GB | Best quality, needs GPU |

**OS:** Rocky Linux 9 (or RHEL 9 / AlmaLinux 9) — x86_64 only

---

## Documentation

| Document | Contents |
|----------|---------|
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | System overview, data flow, directory layout, port table |
| [docs/INSTALL.md](docs/INSTALL.md) | Step-by-step installation guide |
| [docs/CONFIGURE.md](docs/CONFIGURE.md) | Identity files, heartbeat tasks, openclaw.json settings |
| [docs/SECURITY.md](docs/SECURITY.md) | Hardening guide, secrets management, firewall rules |
| [docs/TROUBLESHOOT.md](docs/TROUBLESHOOT.md) | Common issues and fixes |
| [docs/ADVANCED.md](docs/ADVANCED.md) | Model switching, custom skills, backups, CLI cheatsheet |

---

## File Layout

```
openclaw-airgap/
├── 00-validate.sh               ← Prerequisites checker
├── 01-prepare-bundle.sh         ← Bundle builder (internet machine)
├── 02-install.sh                ← Installer (air-gapped machine)
├── 03-configure-identity.sh     ← Identity wizard (post-install)
├── 04-health-check.sh           ← Health verification
├── configs/
│   ├── openclaw.json            ← Main config template
│   ├── HEARTBEAT.md             ← Background task list
│   ├── identity/
│   │   ├── SOUL.md              ← Agent personality
│   │   ├── AGENTS.md            ← Operational rules
│   │   ├── TOOLS.md             ← Available capabilities
│   │   ├── user.md              ← Operator profile
│   │   └── memory.md            ← Permanent facts
│   ├── systemd/                 ← Service unit files
│   ├── logrotate/               ← Log rotation config
│   └── workflows/               ← n8n workflow examples
├── ansible/
│   └── deploy.yml               ← Multi-node deployment playbook
└── docs/
    ├── ARCHITECTURE.md
    ├── INSTALL.md
    ├── CONFIGURE.md
    ├── SECURITY.md
    ├── TROUBLESHOOT.md
    └── ADVANCED.md
```

---

## License

This project is provided as-is for self-hosted, air-gapped deployments.
OpenClaw is developed by the OpenClaw project. Mattermost, Ollama, n8n, and PostgreSQL are separate projects with their own licenses.
