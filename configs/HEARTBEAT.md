# Heartbeat Checklist

> This runs every 30 minutes. The agent reads this, executes each task at its
> specified interval, and either acts or replies HEARTBEAT_OK.
>
> Adjust intervals and tasks to match your actual workflow.
> Delete tasks you don't need. Add tasks you check manually today.

tasks:

  - name: daily-log-init
    interval: 24h
    runAt: "07:00"
    prompt: |
      Create today's daily log at memory/$(date +%Y-%m-%d).md if it doesn't exist.
      Header: "# Daily Log — $(date +%Y-%m-%d)\n\n## Actions\n\n## Notes\n"
      Then read yesterday's log and surface any unresolved items in a brief DM.

  - name: system-health
    interval: 1h
    prompt: |
      Run quick health checks:
      - All required services running? (openclaw, ollama, mattermost, n8n)
      - Disk usage > 85% on any partition?
      - Any failed systemd units?
      If everything is fine, reply HEARTBEAT_OK.
      If anything needs attention, send a DM with specifics.

  - name: pending-tasks
    interval: 30m
    prompt: |
      Check workspace/tasks/ for any .md files with status: pending or blocked.
      If any task is stale (not updated in > 24h), surface it in a brief DM.
      If nothing is pending, reply HEARTBEAT_OK.

  - name: log-rotation-check
    interval: 24h
    runAt: "02:00"
    prompt: |
      Check /var/log/openclaw/ for log files > 100MB.
      Compress any logs older than 7 days.
      Report in the daily log only, do not DM unless total log size > 1GB.

# ─── Future tasks (uncomment and configure as you build out workflows) ────────

  # - name: inbox-triage
  #   interval: 30m
  #   prompt: |
  #     Check the agent email inbox via AgentMail or local SMTP for new messages.
  #     Summarize anything actionable in a brief DM. Skip newsletters and FYIs.

  # - name: news-brief
  #   interval: 24h
  #   runAt: "07:30"
  #   prompt: |
  #     Using the morning-brief skill, scrape configured sources and send a
  #     morning briefing to the #briefings Mattermost channel.

  # - name: backup-check
  #   interval: 24h
  #   runAt: "06:00"
  #   prompt: |
  #     Verify last backup completed successfully (check /var/log/backup.log).
  #     If last backup was > 25h ago, send a DM.

  # - name: trading-monitor
  #   interval: 6h
  #   activeHours: { start: "09:30", end: "16:00" }
  #   prompt: |
  #     Run the trading-monitor skill. Check open positions vs strategy rules.
  #     Report P&L and any required actions in the #trading Mattermost channel.
