#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import sys
import re
import math
import subprocess
import argparse

# --- ANSI Color Configuration ---
RED = "\033[1;31m"
GREEN = "\033[1;32m"
YELLOW = "\033[1;33m"
CYAN = "\033[1;36m"
BOLD = "\033[1m"
RESET = "\033[0m"

# --- Exclusions & Whitelists ---
# Files to completely ignore (e.g. templates, documentation, this script itself)
IGNORED_FILES_PATTERNS = [
    r"\.example$",
    r"README\.md$",
    r"\.git-leak-shield\.py$",
    r"\.githooks/.*"
]

# Legitimate public IPs (known DNS, standard gateways) to ignore
IP_WHITELIST = {
    "1.1.1.1", "1.0.0.1", "8.8.8.8", "8.8.4.4", "9.9.9.9", "149.112.112.112"
}

# --- Detection RegEx Patterns ---

# Internal/local domain names
INTERNAL_DOMAINS_RE = re.compile(
    r"\b[a-zA-Z0-9-]+\.(lan|local|home|internal|home\.lan)\b", re.IGNORECASE
)

# IP addresses (v4 & v6)
IPV4_RE = re.compile(r"\b(?:\d{1,3}\.){3}\d{1,3}\b")
IPV6_RE = re.compile(r"\b(?:[a-fA-F0-9]{1,4}:){7}[a-fA-F0-9]{1,4}\b")

# Classic secret patterns (Passwords, keys, tokens)
SECRET_PATTERNS = [
    # General passwords and tokens in config/compose files
    (re.compile(r"\b(password|passwd|secret|mysql_password|postgres_password|admin_password|secret_key|app_secret|db_password)\b\s*[:=]\s*['\" ]?([^'\"\s\$\{\}]+)['\" ]?", re.IGNORECASE), "Suspect password in configuration"),
    # Private SSL/SSH Key
    (re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----"), "SSL/SSH private key"),
    # Gitea / GitHub API Token
    (re.compile(r"\b(gtp|ghp)_[a-zA-Z0-9]{36,40}\b"), "Gitea / GitHub API token"),
    # AWS API Key
    (re.compile(r"\bAKIA[0-9A-Z]{16}\b"), "AWS Access Key ID"),
    # Portainer Access Token (ptr_...)
    (re.compile(r"\bptr_[a-zA-Z0-9]{40,64}\b"), "Portainer API access token")
]

# --- Helper Functions ---

def should_ignore_file(filepath):
    """Determine if a file should be ignored."""
    for pattern in IGNORED_FILES_PATTERNS:
        if re.search(pattern, filepath):
            return True
    return False

def calculate_entropy(s):
    """Calculate the Shannon entropy of a string."""
    if not s:
        return 0.0
    probabilities = [float(s.count(c)) / len(s) for c in set(s)]
    entropy = - sum(p * math.log(p, 2) for p in probabilities)
    return entropy

def check_entropy_secret(text):
    """Detect high entropy keys (like generated API keys/passwords)."""
    # Look for typical key/token assignment strings
    pattern = re.compile(r"\b(?:key|token|pass|secret|auth|jwt)\b\s*[:=]\s*['\" ]?([a-zA-Z0-9_\-\.\/+=]{16,})['\" ]?", re.IGNORECASE)
    for match in pattern.finditer(text):
        val = match.group(1)
        # Avoid obvious placeholders
        if any(ph in val.lower() for ph in ["template", "placeholder", "your_", "insert_", "xxx", "valeur", "value"]):
            continue
        entropy = calculate_entropy(val)
        if entropy > 4.2:
            return val, entropy
    return None

def is_private_ip(ip):
    """Check if an IP belongs to RFC 1918 private ranges or loopback."""
    if ip == "127.0.0.1" or ip == "0.0.0.0" or ip == "localhost":
        return True, "Local loopback / localhost"
    
    parts = ip.split('.')
    if len(parts) != 4:
        return False, None
    try:
        p1, p2 = int(parts[0]), int(parts[1])
        if p1 == 10:
            return True, "Class A private network (10.0.0.0/8)"
        if p1 == 172 and (16 <= p2 <= 31):
            return True, "Class B private network (172.16.0.0/12)"
        if p1 == 192 and p2 == 168:
            return True, "Class C private network (192.168.0.0/16)"
    except ValueError:
        pass
    return False, None

def inspect_line(line, filepath, line_num):
    """Analyze a single line and return a list of detected issues."""
    findings = []
    
    # 1. Search for Classic Secrets
    for regex, description in SECRET_PATTERNS:
        match = regex.search(line)
        if match:
            # Avoid placeholder values
            val = match.group(2) if len(match.groups()) >= 2 else match.group(0)
            if not any(ph in val.lower() for ph in ["placeholder", "your_", "insert_", "xxx", "template", "valeur", "value"]):
                findings.append({
                    "type": "SECRET",
                    "desc": f"{description} (detected value: '{val[:3]}...{val[-3:] if len(val) > 6 else ''}')",
                    "match": val
                })

    # 2. High Entropy (Mots de passe ou clés générées complexes)
    entropy_match = check_entropy_secret(line)
    if entropy_match:
        val, entropy = entropy_match
        findings.append({
            "type": "ENTROPY_SECRET",
            "desc": f"Suspect high-entropy string ({entropy:.2f}/8.0)",
            "match": val
        })

    # 3. IP Addresses (Private or Public)
    for ip in IPV4_RE.findall(line):
        if ip in IP_WHITELIST:
            continue
        is_priv, priv_desc = is_private_ip(ip)
        if is_priv:
            findings.append({
                "type": "PRIVATE_IP",
                "desc": f"Internal IP address detected ({priv_desc})",
                "match": ip
            })
        else:
            findings.append({
                "type": "PUBLIC_IP",
                "desc": "External public IP address detected",
                "match": ip
            })
            
    for ip in IPV6_RE.findall(line):
        if ip in ["0:0:0:0:0:0:0:1", "::1"]:
            continue
        findings.append({
            "type": "PUBLIC_IP",
            "desc": "External public IPv6 address detected",
            "match": ip
        })

    # 4. Internal Domains
    for domain in INTERNAL_DOMAINS_RE.findall(line):
        findings.append({
            "type": "INTERNAL_DOMAIN",
            "desc": "Internal domain name or network suffix (.lan, .local, etc.)",
            "match": domain[0] if isinstance(domain, tuple) else domain
        })

    # 5. Hardcoded Volumes and Domains in docker-compose.yml
    is_compose = filepath.endswith("docker-compose.yml") or filepath.endswith("docker-compose.yaml")
    if is_compose:
        # Detect hardcoded host volumes
        vol_match = re.search(r"^\s*-\s*['\"]?([~/][^:]+):([^'\"]+)['\"]?", line)
        if vol_match:
            host_path = vol_match.group(1).strip()
            if "$" not in host_path and "{" not in host_path:
                allowed_prefixes = [
                    "/etc/timezone",
                    "/etc/localtime",
                    "/var/run/docker.sock",
                    "/sys",
                    "/proc",
                    "/dev",
                    "/run/dbus/system_bus_socket",
                    "/etc/ssl/certs"
                ]
                is_allowed = False
                for prefix in allowed_prefixes:
                    if host_path.startswith(prefix):
                        is_allowed = True
                        break
                if not is_allowed:
                    findings.append({
                        "type": "HARDCODED_VOLUME",
                        "desc": f"Hardcoded host volume mount detected: '{host_path}'",
                        "match": host_path
                    })

        # Detect hardcoded Traefik Host rules (public or private domain)
        host_match = re.search(r"Host\([`'\"]([^`'\"]+)[`'\"]\)", line)
        if host_match:
            domain = host_match.group(1).strip()
            if "$" not in domain and "{" not in domain:
                findings.append({
                    "type": "HARDCODED_DOMAIN",
                    "desc": f"Hardcoded domain detected in Host rule: '{domain}'",
                    "match": domain
                })

    return findings

# --- Diff Inspection ---

def parse_diff(diff_content):
    """Parse git diff and extract added/modified lines."""
    current_file = None
    line_num = 0
    findings = {}

    for line in diff_content.splitlines():
        if line.startswith("diff --git"):
            # New file in the diff
            current_file = None
            line_num = 0
            # Extract file path
            match = re.search(r"b/(.+)$", line)
            if match:
                filepath = match.group(1)
                if not should_ignore_file(filepath):
                    current_file = filepath
            continue
        
        if not current_file:
            continue

        if line.startswith("@@"):
            # Chunk header, extract starting line number
            match = re.search(r"\+(\d+)", line)
            if match:
                line_num = int(match.group(1)) - 1
            continue

        if line.startswith("+") and not line.startswith("+++"):
            line_num += 1
            content = line[1:] # Remove '+'
            line_findings = inspect_line(content, current_file, line_num)
            if line_findings:
                if current_file not in findings:
                    findings[current_file] = []
                for f in line_findings:
                    f["line_num"] = line_num
                    f["content"] = content
                    findings[current_file].append(f)
        elif not line.startswith("-"):
            # Unchanged line in diff, increments the line number
            line_num += 1

    return findings

# --- Main Execution ---

def main():
    parser = argparse.ArgumentParser(description="Git Leak Shield - Protect against data/secret leaks")
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--staged", action="store_true", help="Analyze indexed changes (pre-commit)")
    group.add_argument("--commit", type=str, help="Analyze a specific commit or range (post-commit)")
    
    args = parser.parse_args()

    # Get Git diff
    if args.staged:
        cmd = ["git", "diff", "--cached", "--unified=0"]
        mode_desc = "Staged changes (Pre-commit)"
    else:
        cmd = ["git", "diff", f"{args.commit}~1..{args.commit}", "--unified=0"]
        mode_desc = f"Commit {args.commit} (Post-commit)"

    try:
        diff_output = subprocess.check_output(cmd, stderr=subprocess.DEVNULL).decode("utf-8", errors="replace")
    except subprocess.CalledProcessError:
        # Handle the case of the very first commit (without HEAD~1)
        if not args.staged:
            cmd = ["git", "show", args.commit, "--unified=0"]
            try:
                diff_output = subprocess.check_output(cmd).decode("utf-8", errors="replace")
            except Exception as e:
                print(f"{YELLOW}Unable to read commit {args.commit}: {e}{RESET}")
                sys.exit(0)
        else:
            print(f"{RED}Error running git diff.{RESET}")
            sys.exit(1)

    findings = parse_diff(diff_output)

    if not findings:
        sys.exit(0)

    # Report Display
    print(f"\n{RED}█▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀█{RESET}")
    print(f"{RED}█{RESET}  {BOLD}{RED}WARNING: DATA LEAK / SENSITIVE INFORMATION DETECTED{RESET}             {RED}█{RESET}")
    print(f"{RED}█▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄█{RESET}\n")
    print(f"{YELLOW}Detection Mode: {mode_desc}{RESET}")
    
    total_leaks = 0
    for filepath, leaks in findings.items():
        print(f"\n📁 File: {BOLD}{CYAN}{filepath}{RESET}")
        for leak in leaks:
            total_leaks += 1
            print(f"  {RED}⚠ [Line {leak['line_num']}] {leak['desc']}{RESET}")
            
            # Format the line to highlight the sensitive element
            highlighted_line = leak['content'].strip()
            match_str = leak['match']
            if match_str in highlighted_line:
                highlighted_line = highlighted_line.replace(match_str, f"{RED}{BOLD}{match_str}{RESET}{YELLOW}")
            
            print(f"    {YELLOW}> {highlighted_line}{RESET}")

    print(f"\n{BOLD}{RED}Conclusion: {total_leaks} critical element(s) detected.{RESET}")
    
    if args.staged:
        print(f"\n{YELLOW}💡 Action blocked! Fix the files or remove the sensitive information.{RESET}")
        print(f"{YELLOW}   To bypass this check temporarily, run: git commit --no-verify{RESET}\n")
    else:
        print(f"\n{YELLOW}💡 The commit was recorded but contains sensitive elements!{RESET}")
        print(f"{YELLOW}   To undo the commit and modify files: git reset HEAD~1{RESET}\n")

    sys.exit(1)

if __name__ == "__main__":
    main()
