#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "$0")/../.." && pwd)"
cd "$ROOT_DIR"
[[ -f .env ]] || { echo "Not bootstrapped: .env is missing."; exit 1; }
set -a
source "$ROOT_DIR/.env"
set +a

if vpn_detail="$(/bin/bash "$ROOT_DIR/scripts/portable/check-vpn.sh" 2>&1)"; then
  vpn_status=active
else
  vpn_status=inactive
fi
echo "VPN: $vpn_status${vpn_detail:+ — $vpn_detail}"
if docker ps --format '{{.Names}}' | grep -qx movienook-qbittorrent; then
  if /bin/bash "$ROOT_DIR/scripts/portable/check-vpn.sh" --verify-qbittorrent >/dev/null 2>&1; then
    echo 'qBittorrent VPN egress: verified'
  else
    echo 'qBittorrent VPN egress: NOT VERIFIED'
  fi
fi
echo
docker compose --env-file .env ps
echo
printf '%-14s %-8s %s\n' "Service" "Status" "Local URL"
check_url() {
  local name="$1" url="$2" accepted="$3" result
  result="$(curl -L -sS -o /dev/null -w '%{http_code}' --max-time 5 "$url" || true)"
  if [[ " $accepted " == *" $result "* ]]; then
    printf '%-14s %-8s %s\n' "$name" "ready" "$url"
  else
    printf '%-14s %-8s %s (%s)\n' "$name" "waiting" "$url" "HTTP ${result:-no response}"
  fi
}
check_url "Plex" "http://127.0.0.1:${PLEX_PORT}/identity" "200"
check_url "Radarr" "http://127.0.0.1:${RADARR_PORT}/" "200"
check_url "Sonarr" "http://127.0.0.1:${SONARR_PORT}/" "200"
check_url "Prowlarr" "http://127.0.0.1:${PROWLARR_PORT}/" "200"
check_url "qBittorrent" "http://127.0.0.1:${QBITTORRENT_WEBUI_PORT}/" "200 401"
check_url "SABnzbd" "http://127.0.0.1:${SABNZBD_PORT}/" "200"
check_url "Seerr" "http://127.0.0.1:${SEERR_PORT}/" "200"
echo
df -h "$ROOT_DIR" | tail -1
