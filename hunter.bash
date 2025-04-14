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

  # === Write to CSV ===
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

  # === Write to temp JSON ===
  echo "$nmap_output" | awk -v ip="$ip" -v ts="$timestamp" '
    BEGIN { print "[" }
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
    END { print "{}]" }
  ' | sed '$!s/},/},/' | sed '$s/{}/ /' > "$TMP_JSON/$ip.json"
}

# ========== MAIN ==========
subnets=("$@")
if [ ${#subnets[@]} -eq 0 ]; then
  echo "Usage: $0 <subnet1> <subnet2> ..."
  echo "Example: $0 198.17.0.0/30 198.18.0.0/30"
  exit 1
fi

for subnet in "${subnets[@]}"; do
  echo "[*] Expanding subnet: $subnet"
  ips=$(nmap -sL "$subnet" 2>/dev/null | awk '/Nmap scan report/{print $NF}' | grep -Eo '([0-9]+\.){3}[0-9]+')
  for ip in $ips; do
    while [ "$(jobs | wc -l)" -ge "$THREADS" ]; do
      sleep 0.2
    done
    scan_ip "$ip" &
  done
done

wait

# === Merge JSON Files ===
echo "[" > "$JSON_FILE"#!/bin/bash

# Get the local machine's IP address
local_ip=$(hostname -I | awk '{print $1}')
echo "Local IP Address: $local_ip"

# Define the target network based on the local IP
subnet="${local_ip%.*}.0/24"

# Scan the network for active devices and all ports using nmap
echo "Scanning for active devices in the network: $subnet"
nmap -p- -sP "$subnet" -oG - | awk '/Up$/{print $2}' > active_ips.txt

# Check if arp-scan is installed
if ! command -v arp-scan &> /dev/null; then
    echo "arp-scan could not be found. Please install it to get MAC addresses."
    exit 1
fi

# Prepare CSV and JSON files
csv_file="network_scan_results.csv"
json_file="network_scan_results.json"
echo "IP Address,MAC Address" > "$csv_file"
echo "[" > "$json_file"

# Get MAC addresses for the active IPs
echo "Getting MAC addresses for active devices..."
first_entry=true
while read -r ip; do
    mac=$(arp-scan -l | grep "$ip" | awk '{print $2}')
    if [ -n "$mac" ]; then
        # Append to CSV
        echo "$ip,$mac" >> "$csv_file"

        # Append to JSON
        if [ "$first_entry" = true ]; then
            first_entry=false
        else
            echo "," >> "$json_file"
        fi
        echo "  {"ip": "$ip", "mac": "$mac"}" >> "$json_file"
    fi
done < active_ips.txt

# Close JSON array
echo "]" >> "$json_file"

# Display the results
echo "Active devices and their MAC addresses:"
cat "$csv_file"
echo "Results saved in $csv_file and $json_file."

find "$TMP_JSON" -type f -name '*.json' -exec cat {} + | sed '$!s/],/],/' >> "$JSON_FILE"
echo "]" >> "$JSON_FILE"

echo "✅ Done. Output saved to:"
echo "  - $CSV_FILE"
echo "  - $JSON_FILE"
