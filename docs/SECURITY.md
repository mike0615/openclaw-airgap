# OpenClaw Security Guide

## Default Security Posture

Out of the box, OpenClaw is configured with these security defaults:

| Setting | Default | Notes |
|---------|---------|-------|
| OpenClaw gateway | Binds to `127.0.0.1` | Not directly accessible from LAN |
| Ollama API | Binds to `127.0.0.1` | No LAN exposure |
| PostgreSQL | Binds to `127.0.0.1` | No LAN exposure |
| n8n password | Randomly generated | Stored in `/etc/openclaw/n8n.env` (perms 600) |
| Mattermost DB password | Randomly generated | Stored in `/root/.mattermost-db-creds` (perms 600) |
| openclaw.json | Owned by agent user, 640 perms | Bot token protected |
| ClawHub (skill marketplace) | Disabled | No outbound skill downloads |
| n8n telemetry | Disabled | No beaconing |
| n8n version checks | Disabled | No outbound connections |

---

## Required Post-Install Actions

### 1. Record and store the n8n password securely

The installer generates a random n8n password and prints it once. If you missed it:
```bash
cat /etc/openclaw/n8n.env
```

Store this in your password manager. The file is root-readable only (`-rw------- root root`).

### 2. Change the Mattermost admin password

The Mattermost admin account is created by you during setup. Ensure it uses a strong password — at least 16 characters.

### 3. Verify the gateway is not exposed to LAN

By default, the OpenClaw gateway binds to `127.0.0.1`. Verify:
```bash
ss -tlnp | grep 18789
# Should show: 127.0.0.1:18789
# NOT: 0.0.0.0:18789
```

If you need LAN access, change `"host"` in openclaw.json to your server's IP (not `0.0.0.0`), then protect it with firewall rules.

### 4. Verify Mission Control source

If you installed Mission Control (optional dashboard), verify the upstream source has no outbound calls before running in production:
```bash
grep -r "fetch\|XMLHttpRequest\|axios\|http" /opt/mission-control/src/ 2>/dev/null | grep -v localhost | grep -v "127.0.0"
```

---

## Secrets Locations and Permissions

| File | Contents | Owner | Permissions |
|------|----------|-------|-------------|
| `/etc/openclaw/n8n.env` | n8n admin password | root | 600 |
| `/root/.mattermost-db-creds` | PostgreSQL mmuser password | root | 600 |
| `/opt/openclaw/.openclaw/openclaw.json` | Mattermost bot token + all config | openclaw | 640 |

Verify permissions:
```bash
ls -la /etc/openclaw/n8n.env
ls -la /root/.mattermost-db-creds
ls -la /opt/openclaw/.openclaw/openclaw.json
```

If any are too open:
```bash
chmod 600 /etc/openclaw/n8n.env
chmod 600 /root/.mattermost-db-creds
chmod 640 /opt/openclaw/.openclaw/openclaw.json
chown openclaw:openclaw /opt/openclaw/.openclaw/openclaw.json
```

---

## Port Exposure and Firewall Rules

### Recommended firewall configuration

The installer opens these ports to all interfaces. Restrict by source IP if possible:

```bash
# Replace existing broad rules with source-restricted rules:
# (Replace 192.168.10.0/24 with your actual LAN subnet)

# Remove current broad rules:
firewall-cmd --permanent --remove-port=8065/tcp
firewall-cmd --permanent --remove-port=5678/tcp
firewall-cmd --permanent --remove-port=3001/tcp

# Add source-restricted rules:
firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="192.168.10.0/24" port port="8065" protocol="tcp" accept'
firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="192.168.10.0/24" port port="5678" protocol="tcp" accept'
firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="192.168.10.0/24" port port="3001" protocol="tcp" accept'

firewall-cmd --reload
```

### Port risk table

| Port | Service | Risk if exposed | Mitigation |
|------|---------|----------------|------------|
| 18789 | OpenClaw | High — unauthenticated API | Bind to 127.0.0.1 by default (done) |
| 11434 | Ollama | Medium — unrestricted LLM access | Bound to 127.0.0.1 (do not change) |
| 5432 | PostgreSQL | High — database access | Bound to 127.0.0.1 (do not change) |
| 8065 | Mattermost | Low — requires auth | Restrict to LAN subnet |
| 5678 | n8n | Medium — workflow execution | Restrict to LAN subnet + use strong password |
| 3001 | Mission Control | Low — read-only dashboard | Restrict to LAN subnet |

---

## Optional Security Hardening

### SELinux

SELinux in enforcing mode provides mandatory access control. If enabled:

```bash
# Check status:
sestatus

# If services are blocked, generate policy:
ausearch -c 'openclaw' --raw | audit2allow -M openclaw-policy
semodule -i openclaw-policy.pp

# Same for ollama, mattermost, n8n if needed
```

To enable enforcing mode (test in permissive first):
```bash
setenforce permissive   # temporary — survives until reboot
sed -i 's/SELINUX=permissive/SELINUX=enforcing/' /etc/selinux/config  # permanent
```

### Mattermost TLS (HTTPS)

For production deployments, enable TLS on Mattermost:

```bash
# Generate self-signed cert (or use your internal CA):
openssl req -x509 -nodes -days 3650 \
  -newkey rsa:4096 \
  -keyout /opt/mattermost/config/server.key \
  -out    /opt/mattermost/config/server.crt \
  -subj "/CN=$(hostname)/O=OpenClaw/C=US"

chmod 600 /opt/mattermost/config/server.key
chown mattermost:mattermost /opt/mattermost/config/server.*
```

Update `/opt/mattermost/config/config.json`:
```json
"ServiceSettings": {
  "SiteURL": "https://YOUR_HOST:8065",
  "ConnectionSecurity": "TLS",
  "TLSCertFile": "./config/server.crt",
  "TLSKeyFile":  "./config/server.key"
}
```

```bash
systemctl restart mattermost
```

### Restrict openclaw user filesystem access

OpenClaw runs as the `openclaw` user and naturally cannot access `/root` or other users' home directories. For additional restriction, use ACLs:

```bash
# Verify openclaw can't touch /root:
sudo -u openclaw ls /root   # Should fail: Permission denied

# Explicitly deny access to /etc/shadow and other sensitive files:
setfacl -m u:openclaw:--- /etc/shadow /etc/gshadow 2>/dev/null || true
```

---

## Log Monitoring

Critical logs to monitor for security events:

```bash
# Failed logins:
grep "Failed password\|Invalid user" /var/log/secure | tail -20

# OpenClaw errors:
tail -f /var/log/openclaw/gateway-error.log

# Mattermost errors:
tail -f /var/log/openclaw/mattermost-error.log

# All OpenClaw services:
journalctl -u openclaw -u ollama -u mattermost -u n8n --since "1 hour ago"
```

The `security-scan` heartbeat task automatically alerts you if SSH failures exceed 10 in 24 hours.

---

## Password Rotation

### Rotate n8n password

```bash
NEW_PASS=$(openssl rand -base64 24 | tr -d '/+=')
cat > /etc/openclaw/n8n.env << EOF
N8N_BASIC_AUTH_PASSWORD=${NEW_PASS}
EOF
chmod 600 /etc/openclaw/n8n.env
systemctl restart n8n
echo "New n8n password: $NEW_PASS"
```

### Rotate Mattermost DB password

```bash
NEW_PASS=$(openssl rand -base64 24 | tr -d '/+=')

# Update PostgreSQL:
sudo -u postgres psql -c "ALTER USER mmuser WITH PASSWORD '${NEW_PASS}';"

# Update Mattermost config:
python3 << EOF
import json
cfg_path = '/opt/mattermost/config/config.json'
with open(cfg_path) as f:
    cfg = json.load(f)
ds = cfg['SqlSettings']['DataSource']
import re
cfg['SqlSettings']['DataSource'] = re.sub(r'mmuser:[^@]+@', f'mmuser:{NEW_PASS}@', ds)
with open(cfg_path, 'w') as f:
    json.dump(cfg, f, indent=2)
print("Updated.")
EOF

# Update creds file:
sed -i "s/DB_PASS=.*/DB_PASS=${NEW_PASS}/" /root/.mattermost-db-creds

systemctl restart mattermost
```

### Rotate Mattermost bot token

1. In Mattermost admin: System Console → Integrations → Bot Accounts → `openclaw-agent` → Regenerate Token
2. Copy the new token
3. Run: `sudo openclaw-configure-mattermost <NEW_TOKEN>`

---

## What NOT to Do

- **Do not expose Ollama (11434) or PostgreSQL (5432) to any network.** These have no authentication by default.
- **Do not expose the OpenClaw gateway (18789) to the internet.** It has no authentication layer — only trust your LAN.
- **Do not run services as root.** All services run under dedicated system users (`openclaw`, `ollama`, `mattermost`).
- **Do not put API keys or tokens in HEARTBEAT.md or identity files.** These files are readable by the agent and may appear in LLM responses.
- **Do not enable ClawHub** (`skills.clawhub.enabled: true`) — this would allow outbound skill downloads, which breaks air-gap.
- **Do not share the Mattermost admin account.** Create individual user accounts for each team member.
- **Do not use weak passwords.** The installer generates strong random passwords; don't replace them with `changeme`.
