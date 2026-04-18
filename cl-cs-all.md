
## PHASE 0 — First 5 Minutes (Run Everything in Parallel)

```bash
# Who am I, where am I
id && whoami && hostname && ip a && cat /etc/hosts

# What OS / kernel
uname -a && cat /etc/os-release

# What's running
ps aux
ss -tlnp
systemctl list-units --type=service --state=running 2>/dev/null
docker ps 2>/dev/null                  # are services containerized?
```

---

## PHASE 1 — Full System Recon

### Map the Services
```bash
# Find all service directories
ls /opt/ /srv/ /var/www/ /home/ /app/ /root/ 2>/dev/null

# Find all listening ports and what owns them
ss -tlnp
netstat -tlnp 2>/dev/null

# Trace each port to its process to its files
ls -la /proc/<PID>/exe          # what binary
ls -la /proc/<PID>/cwd          # working directory
cat /proc/<PID>/cmdline | tr '\0' ' '   # full command

# Find all running scripts
find /opt /srv /var/www /app -name "*.py" -o -name "*.php" \
  -o -name "*.js" -o -name "*.rb" -o -name "*.go" 2>/dev/null
```

### Map the Network
```bash
# Full network picture
ip a                            # your IPs
ip route                        # routing table
cat /etc/hosts                  # known hosts

# Who else is on the network (enemy teams)
# Your IP is e.g. 10.10.1.2 — enemies are 10.10.2.2, 10.10.3.2 etc.
# Confirm the subnet
ip a | grep inet

# Scan enemy team IPs (same services, different IPs)
# Usually competition gives you the IP range
for i in $(seq 1 20); do
  ping -c1 -W1 10.10.$i.1 &>/dev/null && echo "10.10.$i.1 UP"
done

# See open ports on an enemy (for your attackers)
# nc -zv 10.10.2.1 1-9999 2>&1 | grep succeeded   # slow
for port in 80 443 8080 8000 5000 3000 4000 9000; do
  nc -zv -w1 10.10.2.1 $port 2>&1 | grep -i "open\|succeeded"
done
```

### Map the Flags
```bash
# Find all flags — try everything
find / -name "flag*" -type f 2>/dev/null
find / -name "*.flag" -type f 2>/dev/null
find / -path "*/flags/*" -type f 2>/dev/null
find / -name "flag" -type f 2>/dev/null

# Check common CTF flag locations
ls -la /flag /root/flag /root/flag.txt /home/*/flag* 2>/dev/null
find /opt /srv /var/www /app -name "flag*" 2>/dev/null

# Search by flag format (adjust to your competition)
grep -r "FLAG{" / 2>/dev/null
grep -r "CTF{" / 2>/dev/null
```

---

## PHASE 2 — Lock Down Flags

```bash
# For every flag file found:
FLAG="/path/to/flag"

# 1. Backup a copy for yourself
cp $FLAG ~/flag_backup_$(date +%s)

# 2. Lock permissions
chown root:root $FLAG
chmod 400 $FLAG

# 3. Make immutable — attacker with shell can't read or overwrite
chattr +i $FLAG

# 4. Lock the parent directory
chmod 700 $(dirname $FLAG)
chown root:root $(dirname $FLAG)

# 5. Verify
lsattr $FLAG
ls -la $FLAG
```

### If Flags Are Inside Docker Containers
```bash
# List containers
docker ps

# Enter each
docker exec -it <container_id> /bin/sh

# Inside container — repeat the above
find / -name "flag*" 2>/dev/null
chown root:root /path/to/flag
chmod 400 /path/to/flag
chattr +i /path/to/flag 2>/dev/null || echo "chattr not available"
chmod 700 $(dirname /path/to/flag)
exit
```

### Verify the Lock as a Non-Root User
```bash
# Switch to the service user and try to read — should fail
su -s /bin/sh <serviceuser> -c "cat /path/to/flag"
# Expected: Permission denied

# Confirm you (root) can still read it
cat /path/to/flag
```

---

## PHASE 3 — Lock Down the System

### Users & Authentication
```bash
# List all real users
cat /etc/passwd | grep -v nologin | grep -v false | grep -v sync

# Change ALL passwords immediately
passwd root
for user in $(cat /etc/passwd | grep -v nologin | grep -v false | awk -F: '$3>=1000{print $1}'); do
  echo "Changing password for $user"
  passwd $user
done

# Check and clean SSH authorized keys
cat ~/.ssh/authorized_keys
cat /home/*/.ssh/authorized_keys 2>/dev/null
# Remove any keys you don't recognize
echo "" > ~/.ssh/authorized_keys   # nuclear option — wipe all keys

# Disable SSH password auth (if you use keys only)
# sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
# systemctl restart sshd

# Lock accounts you don't need
passwd -l <suspicious_user>
```

### File System Hardening
```bash
# Find all SUID binaries — these can be exploited for privilege escalation
find / -perm -4000 -type f 2>/dev/null

# Remove SUID from binaries that don't need it
# (be careful — some are needed for the OS to function)
chmod u-s /path/to/suspicious_suid_binary

# Find world-writable directories (attackers can drop files here)
find / -type d -perm -0002 2>/dev/null | grep -v proc | grep -v sys

# Fix world-writable dirs in service directories
find /opt /srv /var/www /app -type d -perm -0002 2>/dev/null \
  -exec chmod o-w {} \;

# Find world-writable files in service dirs
find /opt /srv /var/www /app -type f -perm -0002 2>/dev/null \
  -exec chmod o-w {} \;
```

### Cron & Persistence Points
```bash
# Check all cron locations
crontab -l
crontab -l -u root
cat /etc/crontab
ls -la /etc/cron.d/
ls -la /etc/cron.hourly/ /etc/cron.daily/
cat /var/spool/cron/crontabs/* 2>/dev/null

# Baseline it — save current state
crontab -l > ~/cron_baseline.txt
cat /etc/cron.d/* >> ~/cron_baseline.txt

# Check for new entries every 10 min (run this later to diff)
diff <(cat ~/cron_baseline.txt) <(crontab -l)
```

### Systemd & Init
```bash
# List all services
systemctl list-units --type=service

# Check for unexpected services
ls /etc/systemd/system/
ls /lib/systemd/system/

# Baseline
systemctl list-units --type=service > ~/services_baseline.txt

# Look for new ones later
diff ~/services_baseline.txt <(systemctl list-units --type=service)
```

---

## PHASE 4 — Patch Services

### Run the Full Vuln Scan on Each Service
```bash
#!/bin/bash
# Save as ~/scan.sh — run on each service directory

TARGET=${1:-.}
echo "=== VULN SCAN: $TARGET ==="

echo -e "\n[SQLi]"
grep -rn "execute\|query" $TARGET | grep -E '(%s|\.format\(|f"|f'"'"'|\+ )' | grep -v ".bak"

echo -e "\n[CMDi]"
grep -rn "os\.system\|popen\|shell=True\|exec(\|system(\|passthru(\|shell_exec(" $TARGET | grep -v ".bak"

echo -e "\n[XSS]"
grep -rn "echo\|print\|innerHTML\|document\.write" $TARGET | grep -v "htmlspecialchars\|escape\|textContent\|\.bak"

echo -e "\n[LFI/Path Traversal]"
grep -rn "open(\|fopen\|include(\|require(\|send_file\|readfile(" $TARGET | grep -v "\.bak\|^import"

echo -e "\n[Deserialization]"
grep -rn "pickle\.loads\|unserialize(\|yaml\.load\b\|eval(\|exec(" $TARGET | grep -v ".bak"

echo -e "\n[Weak Crypto]"
grep -rn "md5(\|sha1(\|random\.\|rand()\|Math\.random" $TARGET | grep -v ".bak"

echo -e "\n[Hardcoded Secrets]"
grep -rn "password\s*=\s*['\"].\|secret\s*=\s*['\"].\|token\s*=\s*['\"].\|key\s*=\s*['\"]." $TARGET | grep -v ".bak"

echo -e "\n[Debug Mode]"
grep -rn "DEBUG\s*=\s*True\|debug=True\|display_errors\s*=\s*On\|app\.run(debug" $TARGET | grep -v ".bak"

echo -e "\n[File Upload]"
grep -rn "move_uploaded_file\|\.save(\|f\.write" $TARGET | grep -v ".bak"

echo -e "\n[SSRF]"
grep -rn "requests\.get\|requests\.post\|urllib\|file_get_contents\|curl" $TARGET | grep -v ".bak"

echo -e "\n[XXE]"
grep -rn "xml\|etree\|lxml\|parseString\|minidom" $TARGET | grep -v ".bak"

echo "=== DONE ==="
```

```bash
chmod +x ~/scan.sh

# Run on each service
~/scan.sh /opt/service1
~/scan.sh /opt/service2
# etc.
```

---

## PHASE 5 — Monitoring Loop

### Watch for Attacks in Real Time
```bash
# Watch web access logs
tail -f /var/log/apache2/access.log
tail -f /var/log/nginx/access.log
tail -f /opt/service1/logs/*.log

# Filter for suspicious patterns
tail -f /var/log/nginx/access.log | grep -E "\.\.\/|UNION|SELECT|<script|eval\(|base64|/etc/passwd|cmd="

# Watch active connections per service port
watch -n2 "ss -tnp | grep ':8080\|:5000\|:3000'"
```

### Watch for File Changes (Backdoor Drops)
```bash
# Monitor service directories for changes
while true; do
  find /opt /srv /var/www /app -newer /tmp/.lastcheck -type f 2>/dev/null \
    | grep -v ".pyc\|__pycache__\|.log" \
    | while read f; do echo "[CHANGED] $f"; done
  touch /tmp/.lastcheck
  sleep 30
done &
```

### Periodic Backdoor Scan
```bash
#!/bin/bash
# Save as ~/monitor.sh and run in background: bash ~/monitor.sh &

while true; do
  echo "=== SCAN $(date) ==="

  echo "[Suspicious processes]"
  ps aux | grep -E "nc |ncat|netcat|bash -i|/dev/tcp|python -c|perl -e|mkfifo" | grep -v grep

  echo "[New SUID]"
  find / -perm -4000 -type f 2>/dev/null > /tmp/suid_now.txt
  diff /tmp/suid_baseline.txt /tmp/suid_now.txt 2>/dev/null | grep "^>"

  echo "[New listening ports]"
  ss -tlnp > /tmp/ports_now.txt
  diff /tmp/ports_baseline.txt /tmp/ports_now.txt 2>/dev/null | grep "^>"

  echo "[/tmp and /dev/shm]"
  ls -la /tmp /dev/shm | grep -v "^total\|^\."

  echo "[New cron]"
  diff ~/cron_baseline.txt <(crontab -l 2>/dev/null) | grep "^>"

  echo "[Outbound connections]"
  ss -tnp | grep ESTABLISHED

  sleep 300   # every 5 minutes
done
```

```bash
# Create baselines first
find / -perm -4000 -type f 2>/dev/null > /tmp/suid_baseline.txt
ss -tlnp > /tmp/ports_baseline.txt

# Run monitor in background
bash ~/monitor.sh &
```

---

## PHASE 6 — Container-Specific Hardening

```bash
# Enter every container and harden
for container in $(docker ps -q); do
  name=$(docker inspect --format='{{.Name}}' $container)
  echo "=== Hardening $name ==="

  docker exec $container sh -c "
    # Find and lock flags
    find / -name 'flag*' -type f 2>/dev/null | while read f; do
      chown root:root \$f
      chmod 400 \$f
      chattr +i \$f 2>/dev/null
      chmod 700 \$(dirname \$f)
      echo Locked: \$f
    done

    # Clean /tmp
    rm -rf /tmp/* /dev/shm/* 2>/dev/null

    # Check users
    cat /etc/passwd | grep -v nologin | grep -v false

    # Check listening ports inside container
    ss -tlnp 2>/dev/null || netstat -tlnp 2>/dev/null
  "
done
```

---

## PHASE 7 — Ongoing Checklist (Every 10-15 Min)

```bash
#!/bin/bash
# Save as ~/check.sh — run manually every rotation

echo "=== HEALTH CHECK $(date) ==="

echo "[Services still up?]"
ss -tlnp | grep LISTEN

echo "[Flags still locked?]"
find / -name "flag*" -type f 2>/dev/null | while read f; do
  echo "$f: $(ls -la $f) | $(lsattr $f 2>/dev/null)"
done

echo "[New files in /tmp?]"
ls -la /tmp /dev/shm 2>/dev/null

echo "[New processes?]"
ps aux | grep -v "your_known_services"

echo "[Active attacker connections?]"
ss -tnp | grep ESTABLISHED

echo "[Auth log — recent logins]"
tail -20 /var/log/auth.log 2>/dev/null
last | head -10
```
