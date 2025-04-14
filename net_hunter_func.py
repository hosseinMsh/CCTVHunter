import subprocess
import ipaddress
import csv
import json
import os
import re
import threading
from datetime import datetime
from concurrent.futures import ThreadPoolExecutor, as_completed

# Configuration
csv_file = "cctv_scan_results.csv"
json_file = "cctv_scan_results.json"
max_threads = 50
csv_lock = threading.Lock()
json_results = []

# Clear old outputs
if os.path.exists(csv_file):
    os.remove(csv_file)

# Create CSV file with header
with open(csv_file, 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(["IP", "Port", "Protocol", "Service", "State", "Extra Info", "Timestamp"])

def run_nmap_scan(ip):
    print(f"[*] Scanning {ip} with nmap...")
    try:
        result = subprocess.run(
            ["nmap", "-T4", "-A", "-v", ip],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=90
        )
        output = result.stdout.decode()
        parsed = parse_nmap_output(ip, output)
        return parsed
    except subprocess.TimeoutExpired:
        print(f"[!] Timeout scanning {ip}")
        return []
    except Exception as e:
        print(f"[!] Error scanning {ip}: {e}")
        return []

def parse_nmap_output(ip, output):
    results = []
    lines = output.splitlines()

    for line in lines:
        line = line.strip()
        if line.startswith("PORT"):
            continue
        elif re.match(r"^\d+\/\w+", line):
            parts = line.split(None, 4)
            if len(parts) >= 3:
                port_proto = parts[0]
                state = parts[1]
                service = parts[2]
                extra = parts[3] if len(parts) > 3 else ""
                port, proto = port_proto.split('/')
                entry = {
                    "ip": ip,
                    "port": port,
                    "protocol": proto,
                    "state": state,
                    "service": service,
                    "extra": extra,
                    "timestamp": datetime.now().isoformat()
                }
                results.append(entry)
    return results

def write_results_to_csv(results):
    if not results:
        return
    with csv_lock:
        with open(csv_file, 'a', newline='') as f:
            writer = csv.writer(f)
            for entry in results:
                writer.writerow([
                    entry['ip'],
                    entry['port'],
                    entry['protocol'],
                    entry['service'],
                    entry['state'],
                    entry['extra'],
                    entry['timestamp']
                ])

def scan_subnets(subnets):
    print(f"[*] Starting scan of subnets: {', '.join(subnets)} with {max_threads} threads...\n")
    all_hosts = []
    for subnet in subnets:
        network = ipaddress.ip_network(subnet, strict=False)
        all_hosts.extend([str(ip) for ip in network.hosts()])

    with ThreadPoolExecutor(max_threads) as executor:
        futures = {executor.submit(run_nmap_scan, ip): ip for ip in all_hosts}
        for future in as_completed(futures):
            ip = futures[future]
            try:
                results = future.result()
                if results:
                    write_results_to_csv(results)  # Thread-safe CSV write
                    json_results.extend(results)   # Save for final JSON
            except Exception as e:
                print(f"[!] Error processing {ip}: {e}")

    # Save all results to JSON at the end
    with open(json_file, 'w') as f:
        json.dump(json_results, f, indent=2)

    print(f"\n✅ Scanning complete. Results saved to:\n - {csv_file}\n - {json_file}")

# Example direct usage
if __name__ == '__main__':
    scan_subnets([
        '172.17.0.0/16', '172.18.0.0/15', '172.20.0.0/14', '172.22.0.0/15'
    ])
