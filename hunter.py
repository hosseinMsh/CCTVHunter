import socket
import ipaddress
import subprocess
import requests
import re
from concurrent.futures import ThreadPoolExecutor, as_completed

# Config
subnet = '172.17.0.0/16'
ports_to_scan = [80, 443, 554, 8000, 8080, 8888, 81, 82, 85]
timeout = 1
max_threads = 100
output_file = "cctv_scan_results.txt"

# Clear output
with open(output_file, 'w') as f:
    f.write("CCTV Scan Results\n=================\n")

def grab_http_banner(ip, port):
    url = f"http://{ip}:{port}"
    try:
        r = requests.get(url, timeout=2)
        title = re.search(r'<title>(.*?)</title>', r.text, re.IGNORECASE)
        return f"HTTP {r.status_code} | Server: {r.headers.get('Server', 'Unknown')} | Title: {title.group(1) if title else 'N/A'}"
    except:
        return "No HTTP response"

def check_rtsp(ip):
    try:
        result = subprocess.run(
            ['ffprobe', '-v', 'error', '-rtsp_transport', 'tcp', '-i', f'rtsp://{ip}:554'],
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=5
        )
        return "RTSP stream detected" if "Stream" in result.stdout.decode() else "No RTSP"
    except:
        return "RTSP check failed"

def get_mac_vendor(ip):
    try:
        arp = subprocess.check_output(["arp", "-n", ip]).decode()
        mac = re.search(r"(([a-fA-F0-9]{2}[:-]){5}[a-fA-F0-9]{2})", arp)
        if mac:
            prefix = mac.group(0).upper()[0:8].replace(":", "-")
            return f"MAC: {mac.group(0)} | Vendor: Lookup needed ({prefix})"
        return "MAC not found"
    except:
        return "MAC lookup failed"

def scan_host(ip):
    open_ports = []
    findings = []
    for port in ports_to_scan:
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
                s.settimeout(timeout)
                s.connect((ip, port))
                open_ports.append(port)
        except:
            continue

    if open_ports:
        findings.append(f"{ip}: Open ports {open_ports}")
        for port in open_ports:
            if port in [80, 8080, 8000, 8888, 81, 82]:
                findings.append(f"  [HTTP {port}] -> {grab_http_banner(ip, port)}")
        if 554 in open_ports:
            findings.append(f"  [RTSP 554] -> {check_rtsp(ip)}")
        findings.append(f"  [MAC Info] -> {get_mac_vendor(ip)}")

        with open(output_file, 'a') as f:
            f.write("\n".join(findings) + "\n\n")
        print("\n".join(findings) + "\n")

# Main
def main():
    print(f"[*] CCTV Hunter starting on subnets: {', '.join(subnets)} with {max_threads} threads...\n")
    with ThreadPoolExecutor(max_threads) as executor:
        futures = []
        for subnet in subnets:
            network = ipaddress.ip_network(subnet, strict=False)
            futures.extend(executor.submit(scan_host, str(ip)) for ip in network.hosts())
        for _ in as_completed(futures):
            pass

if __name__ == '__main__':
    main()
