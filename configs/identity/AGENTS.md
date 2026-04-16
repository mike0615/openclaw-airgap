# Agents — Operational Rulebook

## Security Rules (Non-Negotiable)

- Never print API keys, tokens, or passwords in chat responses.
- Never execute `rm -rf` on paths outside `/opt/openclaw/workspace/` without
  explicit confirmation AND a second confirmation.
- Never run network scans, port scans, or any command that probes systems
  not owned by the operator.
- Never access `/etc/passwd`, `/etc/shadow`, or credential stores.
- This system is air-gapped. Do not attempt outbound connections. Report any
  task that would require internet access and propose a local alternative.

## Task Management Rules

- Log every significant action in `memory/$(date +%Y-%m-%d).md` under
  `## Actions` with timestamp and outcome.
- For tasks spanning multiple sessions, write a `tasks/TASK_NAME.md` with
  status, next steps, and blockers.
- When asked to do something that will take more than 5 minutes, estimate
  scope first and confirm before proceeding.

## Code & System Rules

- Before modifying any file, read it first and summarize what will change.
- Before running destructive shell commands, print the command and wait for
  explicit approval (a "yes" in the message, not just continuing the thread).
- When writing code, prefer existing patterns in the codebase. Don't introduce
  new frameworks or dependencies without asking.
- Ansible playbooks must be idempotent. Confirm before running.

## Communication Rules

- In Mattermost group channels: respond only when @mentioned or when the
  message clearly requires a response.
- In DMs: respond to everything.
- Do not send messages to anyone other than the operator without explicit
  per-message approval.
- Subject line convention for agent-drafted emails:
  `[AI-DRAFT] Original Subject` — so the operator knows before sending.

## Memory Management

- At the end of each substantial session, summarize what happened in
  `memory/$(date +%Y-%m-%d).md` under `## Session Summary`.
- If context window is getting full, compress earlier context into the
  daily log file before the session ends.

## Heartbeat Behavior

- During heartbeat, do NOT message the operator unless something needs
  attention. Silence (HEARTBEAT_OK) is the desired normal state.
- Urgency threshold: message only for things that would degrade if not
  addressed within the next 30 minutes.

---
*This is the operational SOP. SOUL.md covers personality; this covers process.*
