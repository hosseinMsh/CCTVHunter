#!/bin/bash

# ========== CONFIG ==========
THREADS=10
CSV_FILE="cctv_scan_results.csv"
JSON_FILE="cctv_scan_results.json"
TMP_JSON="tmp_scan_jsons"
mkdir -p "$TMP_JSON"

# ========== INIT ==========
echo "IP,Port,Protocol,Service,State,Extra Info,Timestamp" > "$CSV_FILE"
rm -f "$TMP_JSON"/*.json

# ========== FUNC ==========
scan_ip() {
  local ip="$1"
  echo "[*] Scanning $ip..."
  local timestamp
  timestamp=$(date -Iseconds)

  local nmap_output
  nmap_output=$(nmap -T4 -A -v "$ip")

  echo "$nmap_output" | awk -v ip="$ip" -v ts="$timestamp" '
    /^PORT/ { in_ports=1; next }
    in_ports && /^[0-9]+\/[a-z]+/ {
      split($1, proto, "/");
      port=proto[1];
      protocol=proto[2];
      state=$2;
      service=$3;
      extra=substr($0, index($0,$4));
      gsub(/"/, "", extra);
      printf "%s,%s,%s,%s,%s,\"%s\",%s\n", ip, port, protocol, service, state, extra, ts;
    }
  ' >> "$CSV_FILE"

  # Create temporary JSON per host
  echo "$nmap_output" | awk -v ip="$ip" -v ts="$timestamp" '
    BEGIN {
      print "["
    }
    /^PORT/ { in_ports=1; next }
    in_ports && /^[0-9]+\/[a-z]+/ {
      split($1, proto, "/");
      port=proto[1];
      protocol=proto[2];
      state=$2;
      service=$3;
      extra=substr($0, index($0,$4));
      gsub(/"/, "", extra);
      printf "{\"ip\":\"%s\",\"port\":\"%s\",\"protocol\":\"%s\",\"service\":\"%s\",\"state\":\"%s\",\"extra\":\"%s\",\"timestamp\":\"%s\"},\n", ip, port, protocol, service, state, extra, ts;
    }
    END {
      print "]"
    }
  ' | sed '$s/},/}/' > "$TMP_JSON/$ip.json"
}

# ========== MAIN ==========
subnets=("$@")
if [ ${#subnets[@]} -eq 0 ]; then
  echo "Usage: $0 <subnet1> <subnet2> ..."
  echo "Example: $0 198.17.0.0/30 198.18.0.0/30"
  exit 1
fi

# Expand IPs and scan in parallel
for subnet in "${subnets[@]}"; do
  ipcalc -nb "$subnet" >/dev/null 2>&1 || { echo "Invalid subnet: $subnet"; continue; }
  ips=$(nmap -sL "$subnet" | awk '/Nmap scan report/{print $NF}' | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+')
  for ip in $ips; do
    while [ "$(jobs | wc -l)" -ge "$THREADS" ]; do
      sleep 0.2
    done
    scan_ip "$ip" &
  done
done

wait

# Merge JSON files into one
echo "[" > "$JSON_FILE"
find "$TMP_JSON" -type f -name '*.json' -exec cat {} + | sed '$!s/],/],/' >> "$JSON_FILE"
echo "]" >> "$JSON_FILE"

echo "✅ Done. Output saved to:"
echo "  - $CSV_FILE"
echo "  - $JSON_FILE"
