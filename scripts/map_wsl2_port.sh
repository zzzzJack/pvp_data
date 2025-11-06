#!/usr/bin/env bash
set -euo pipefail

# WSL2 helper: map Windows host port to current WSL2 IP:port via netsh portproxy
# Requires: running from WSL; will call powershell.exe (Windows side) with admin rights

usage() {
  cat <<USAGE
Usage:
  bash scripts/map_wsl2_port.sh add   [PORT] [TARGET_PORT]
  bash scripts/map_wsl2_port.sh del   [PORT]
  bash scripts/map_wsl2_port.sh show

Defaults:
  PORT=8000, TARGET_PORT=8000

Examples:
  # Map Windows 0.0.0.0:8000 -> WSL2_IP:8000
  bash scripts/map_wsl2_port.sh add 8000 8000

  # Remove mapping on 8000
  bash scripts/map_wsl2_port.sh del 8000

  # Show current mappings
  bash scripts/map_wsl2_port.sh show
USAGE
}

detect_wsl_ip() {
  # Prefer eth0 IPv4
  ip -4 addr show eth0 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 | head -n1
}

ensure_admin_note() {
  echo "NOTE: Windows PowerShell will need Administrator privileges for netsh/firewall rules."
}

add_mapping() {
  local PORT="${1:-8000}"
  local TARGET_PORT="${2:-$PORT}"
  local WSL_IP
  WSL_IP="$(detect_wsl_ip)"
  if [ -z "$WSL_IP" ]; then
    echo "ERROR: Could not detect WSL2 IPv4 on eth0."
    exit 1
  fi
  ensure_admin_note
  powershell.exe -NoProfile -Command "Start-Process powershell -Verb runAs -ArgumentList ' -NoProfile -Command \"$env:ErrorActionPreference=\'Stop\'; \\
    # Open inbound firewall on PORT if missing\\n    if (-not (Get-NetFirewallRule -DisplayName \"WSL2 Port $PORT Inbound\" -ErrorAction SilentlyContinue)) {\\n      New-NetFirewallRule -DisplayName \"WSL2 Port $PORT Inbound\" -Direction Inbound -Action Allow -Protocol TCP -LocalPort $PORT | Out-Null\\n    } \\
    # Remove existing portproxy on PORT to avoid duplicates\\n    netsh interface portproxy delete v4tov4 listenport=$PORT listenaddress=0.0.0.0 | Out-Null; \\
    # Add new mapping to current WSL IP\\n    netsh interface portproxy add v4tov4 listenport=$PORT listenaddress=0.0.0.0 connectport=$TARGET_PORT connectaddress=$WSL_IP; \\
    Write-Host \"Mapped 0.0.0.0:$PORT -> $WSL_IP:$TARGET_PORT\"\"'"
}

del_mapping() {
  local PORT="${1:-8000}"
  ensure_admin_note
  powershell.exe -NoProfile -Command "Start-Process powershell -Verb runAs -ArgumentList ' -NoProfile -Command \"$env:ErrorActionPreference=\'Stop\'; \\
    netsh interface portproxy delete v4tov4 listenport=$PORT listenaddress=0.0.0.0; \\
    if (Get-NetFirewallRule -DisplayName \"WSL2 Port $PORT Inbound\" -ErrorAction SilentlyContinue) {\\n      Remove-NetFirewallRule -DisplayName \"WSL2 Port $PORT Inbound\"\\n    } \\
    Write-Host \"Removed mapping on port $PORT\"\"'"
}

show_mapping() {
  powershell.exe -NoProfile -Command "netsh interface portproxy show v4tov4"
}

cmd="${1:-}"
case "$cmd" in
  add)
    add_mapping "${2:-8000}" "${3:-${2:-8000}}"
    ;;
  del)
    del_mapping "${2:-8000}"
    ;;
  show)
    show_mapping
    ;;
  *)
    usage
    exit 1
    ;;
esac




