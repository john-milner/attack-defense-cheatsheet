### Find Everything
```bash
find / -name "flag*" -type f 2>/dev/null
find / -name "*.flag" -type f 2>/dev/null
find / -path "*/flags/*" 2>/dev/null
```

### Step 2 — Lock Permissions
```bash
# Only root can read it
chmod 600 /path/to/flag        # rw-------
chown root:root /path/to/flag

# Even stricter — only root can read, no write
chmod 400 /path/to/flag        # r--------

# Lock the directory too
chmod 700 /path/to/flag_dir
chown root:root /path/to/flag_dir
```

### Step 3 — Make It Immutable
```bash
# Even root can't modify/delete it (protects from attackers with root)
chattr +i /path/to/flag

# Verify
lsattr /path/to/flag
# shows: ----i---------  /path/to/flag

# To undo when/if needed
chattr -i /path/to/flag
```

### Step 4 — If Inside Docker Containers
```bash
# Get container list
docker ps

# Shell into each one
docker exec -it <container_id> /bin/sh

# Inside — find and lock
find / -name "flag*" 2>/dev/null
chmod 400 /path/to/flag
chown root:root /path/to/flag
chattr +i /path/to/flag        # if chattr available in container
```

### Step 5 — Verify the Lock Works
```bash
# Switch to the service user and try to read
su -s /bin/sh serviceuser -c "cat /path/to/flag"
# Should return: Permission denied

# Confirm root can still read (for your own checker needs)
cat /path/to/flag   # as root — works
```

### Step 6 — Prevent Flag Hunting via Directory Listing
```bash
# Make parent dirs untraversable by others
chmod 701 /                    # careful with this one
chmod 750 /opt/service1
chmod 750 /opt/service1/data

# Specifically block common flag parent dirs
find /opt /srv /var/www -type d -exec chmod o-rx {} \;
```

---

## Bonus — If Attacker Already Has a Shell on Your Box

They'll try:
```bash
find / -name flag* 2>/dev/null        # blocked if dir is 700
cat /proc/1/environ                   # might leak secrets
ls /                                  # traversal attempt
```

Your `chmod 400 + chattr +i + parent dir 700` chain stops all of these cold.
