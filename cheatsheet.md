To capture the exact requests used to steal your flags, you need to implement **Passive Traffic Sniffing**. Since you are on a Linux-based system, your primary tool is `tcpdump`. 

The goal is to find "The Golden Packet"—the specific HTTP request or TCP stream containing the flag string (e.g., `FLAG{...}` or whatever format the game uses).

### 1. Identify the Flag Format
First, look at your own local flag file to see the pattern.
* **Command:** `cat /path/to/flag/file`
* **Identify the prefix:** Does it start with `CTF{`, `GH{`, or just a random hex string? This is your search term.

---

### 2. The `tcpdump` Strategy
Run this on your main network interface (usually `eth0`). You want to see the **ASCII** output (`-A`) of the traffic.

#### A. Watch all traffic for a specific flag pattern
This is the most effective way to catch someone "red-handed."
```bash
# -i eth0: interface
# -A: print payload in ASCII
# -s 0: capture full packet size
# grep: filter for your flag prefix
sudo tcpdump -i eth0 -A -s 0 | grep -i "FLAG{"
```

#### B. Isolate a Specific Service
If Service #3 (on port 8080) is getting hit hard, focus your "camera" there and save it to a file for deeper analysis:
```bash
sudo tcpdump -i eth0 port 8080 -w service3_attacks.pcap
```
You can then read that file back with:
```bash
tcpdump -A -r service3_attacks.pcap | grep "FLAG{"
```

---

### 3. The "Traffic Replay" Workflow
This is how top teams win: **They catch an attack and "reflect" it.**

1.  **Monitor:** Run the `tcpdump` command above.
2.  **Intercept:** An enemy sends a complex SQLi payload. Your terminal flashes with the flag prefix because the server responded to them with your flag.
3.  **Analyze:** Look at the lines *immediately preceding* the flag in the `tcpdump` output. That is the enemy's exploit.
4.  **Clean:** Copy their request (the URL, the POST data, and the Headers).
5.  **Strike:** Use `curl` to send that exact same request to every other team's IP address.

---

### 4. Advanced: Using `ngrep` (Network Grep)
If `ngrep` is installed on the machine, it is much cleaner than `tcpdump` for this specific task:
```bash
# -d eth0: device
# -W byline: keep formatting clean
# "FLAG{": the string to search for
# port 80: only web traffic
sudo ngrep -d eth0 -W byline "FLAG{" port 80
```

---

### 5. Application Layer Logging (The Backup)
If the enemy is using HTTPS (unlikely in A&D but possible) or if `tcpdump` is too noisy, check the service-level logs.
* **Web Services:** `tail -f /var/log/apache2/access.log`
* **Custom Apps:** Check the source code to see if the developer included a `log()` function. If so, `tail -f` that log file. 
* **Pro Tip:** Look for IP addresses that aren't yours and aren't the SLA Checker. If you see an IP hitting a specific endpoint with a long string of weird characters (`%27%20OR%201%3D1`), that’s your attacker.

### Summary Checklist
1.  **Start `tcpdump`** in a dedicated terminal window immediately.
2.  **Find the flag prefix** so you know what to filter for.
3.  **Log to a file** (`.pcap`) so you can scroll back in time if you miss an attack.
4.  **Identify the Attacker IP** to block them if the rules allow, or to prioritize attacking them back.

Since you're used to Jeopardy-style, remember: in A&D, the **logs** are your new best friend. In Jeopardy, the flag is the end; in A&D, the flag in your logs is just the beginning of your counter-attack.
