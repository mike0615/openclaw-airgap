# Heartbeat Checklist

> This runs every 30 minutes. The agent reads this, executes each task at its
> specified interval, and either acts or replies HEARTBEAT_OK.
>
> Adjust intervals and tasks to match your actual workflow.
> Delete tasks you don't need. Add tasks you check manually today.
>
> Run `sudo bash 03-configure-identity.sh` to configure these interactively.

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
      - Any failed systemd units? (systemctl list-units --state=failed)
      - RAM usage > 90%? Check: free -m | awk 'NR==2{printf "Used: %dMB / %dMB (%.0f%%)\n", $3,$2,$3*100/$2}'
      If everything is fine, reply HEARTBEAT_OK.
      If anything needs attention, send a DM with specifics.

  - name: pending-tasks
    interval: 30m
    prompt: |
      Check workspace/tasks/ for any .md files with status: pending or blocked.
      A task file must have "status: pending" or "status: blocked" on its second
      line to be counted (see configs/tasks/TASK_TEMPLATE.md for the format).
      If any task is stale (not updated in > 24h), surface it in a brief DM.
      If nothing is pending, reply HEARTBEAT_OK.

  - name: log-rotation-check
    interval: 24h
    runAt: "02:00"
    prompt: |
      Check /var/log/openclaw/ for log files > 100MB.
      Compress any logs older than 7 days.
      Report in the daily log only, do not DM unless total log size > 1GB.

  - name: security-scan
    interval: 24h
    runAt: "03:00"
    prompt: |
      Check for failed SSH login attempts in the last 24 hours:
        grep "Failed password\|Invalid user" /var/log/secure 2>/dev/null | \
          grep "$(date -d '24 hours ago' +'%b %e')\|$(date +'%b %e')" | wc -l
      If the count exceeds 10, send a DM with the count and top 5 source IPs:
        grep "Failed password\|Invalid user" /var/log/secure 2>/dev/null | \
          grep -oP '(\d{1,3}\.){3}\d{1,3}' | sort | uniq -c | sort -rn | head -5
      If count is 10 or under, reply HEARTBEAT_OK.

  - name: service-restart-alert
    interval: 15m
    prompt: |
      Check if any openclaw-managed service has restarted more than 3 times today:
        for svc in openclaw ollama mattermost n8n; do
          COUNT=$(journalctl -u $svc --since "today" 2>/dev/null | grep -c "Started\|start" || echo 0)
          echo "$svc: $COUNT restarts today"
        done
      If any service has restarted more than 3 times, send a DM with the service name,
      restart count, and last 5 lines of its journal.
      Otherwise reply HEARTBEAT_OK.

  - name: workspace-backup
    interval: 24h
    runAt: "02:30"
    prompt: |
      Create a compressed backup of the memory directory:
        BACKUP_DIR="/opt/openclaw/backups"
        DATE=$(date +%Y-%m-%d)
        mkdir -p "$BACKUP_DIR"
        tar czf "$BACKUP_DIR/$DATE-memory.tar.gz" -C /opt/openclaw/workspace memory/ 2>/dev/null
        echo "Backup created: $BACKUP_DIR/$DATE-memory.tar.gz"
      Then remove backups older than 30 days:
        find "$BACKUP_DIR" -name "*.tar.gz" -mtime +30 -delete
      Log the action in today's daily log. Reply HEARTBEAT_OK.

# ─── Future / opt-in tasks ───────────────────────────────────────────────────
# Uncomment and configure these after you set up the prerequisite components.

  # ── backup-check ─────────────────────────────────────────────────────────
  # Prerequisite: configure a system backup job that writes a status line to
  # /var/log/backup.log (e.g. via cron + rsync/restic/borgbackup).
  # See docs/ADVANCED.md "Backup and Restore Procedure" for an example script.
  # - name: backup-check
  #   interval: 24h
  #   runAt: "06:00"
  #   prompt: |
  #     Check if /var/log/backup.log exists and has an entry from the last 25 hours.
  #     If found, verify the last line does not contain "ERROR" or "FAILED".
  #     If no backup log exists, warn: "No backup log found at /var/log/backup.log —
  #     backup may not be configured."
  #     If last backup was > 25h ago, send a DM with the time of last successful backup.
  #     If backup is current and clean, reply HEARTBEAT_OK.

  # ── inbox-triage ─────────────────────────────────────────────────────────
  # Prerequisite: configure an AgentMail account or a local SMTP relay and
  # add its connection details to memory.md and openclaw.json.
  # - name: inbox-triage
  #   interval: 30m
  #   prompt: |
  #     Check the agent email inbox via AgentMail or local SMTP for new messages.
  #     Summarize anything actionable in a brief DM. Skip newsletters and FYIs.

  # ── news-brief ────────────────────────────────────────────────────────────
  # Prerequisite: install the morning-brief skill
  # (workspace/skills/morning-brief/SKILL.md) and list its sources in TOOLS.md.
  # - name: news-brief
  #   interval: 24h
  #   runAt: "07:30"
  #   prompt: |
  #     Using the morning-brief skill, scrape configured sources and send a
  #     morning briefing to the #briefings Mattermost channel.

  # ── trading-monitor ───────────────────────────────────────────────────────
  # Prerequisite: install the trading-monitor skill and configure brokerage
  # API access (local proxy or file-based feed) in TOOLS.md.
  # - name: trading-monitor
  #   interval: 6h
  #   activeHours: { start: "09:30", end: "16:00" }
  #   prompt: |
  #     Run the trading-monitor skill. Check open positions vs strategy rules.
  #     Report P&L and any required actions in the #trading Mattermost channel.
