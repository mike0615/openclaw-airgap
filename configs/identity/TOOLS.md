# Tools — Available Capabilities

> This file reminds the agent what it has access to on this system.
> Update this whenever you add a new skill or integration.

## Local AI / LLM

- **Ollama** at http://127.0.0.1:11434
  - Primary model: `__MODEL__`
  - Usage: all text generation, reasoning, code
  - Multimodal: depends on model; see `ollama list`

## Communication

- **Mattermost** (self-hosted) at http://__SERVER_HOSTNAME__:8065
  - Bot account: openclaw-agent
  - Channels available: (list your channels after setup)
  - Can post, read, create threads

## System Access

- **Shell execution:** available (see AGENTS.md for rules)
- **File system:** full access to /opt/openclaw/workspace/
  - Partial access (read): /var/log/ (for diagnostics)
  - Restricted: /etc/, /root/, home directories outside workspace

## Automation

- **n8n** at http://127.0.0.1:5678
  - Can create workflows that run on schedule
  - Can trigger webhooks internally
  - Connect to local services via HTTP

## Voice

- **faster-whisper** (local, CPU-based)
  - Invoked via: `openclaw-transcribe <audio-file>`
  - Supported formats: wav, mp3, ogg, m4a, flac
  - Model: base.en (English optimized)
  - For multilingual, replace with `base` or `medium`

## Skills Installed

> Add entries here as you install skills from the bundle or create them.
> Format: `- skill-name: one-line description | invoke with: /skill-name`

- (none yet — add after installation)

## Image Generation

- (not installed by default — see README.md "Optional Components" for ComfyUI setup)

## Database Access

- PostgreSQL 16 (local, used by Mattermost)
  - Connection: postgres://localhost:5432/mattermost
  - Access: via agent user ONLY for read queries; no schema changes without approval

## Monitoring & Diagnostics

- `journalctl -u openclaw` — OpenClaw logs
- `journalctl -u ollama`   — Ollama logs
- `systemctl status openclaw mattermost n8n ollama` — Service status
- Mission Control dashboard: http://__SERVER_HOSTNAME__:3001

---
*Keep this file current. The agent reads it to decide which tool to reach for.*
