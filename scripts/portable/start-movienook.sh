#!/usr/bin/env bash
# Start the self-contained Docker stack. Run with --open to launch Seerr and Plex.
set -euo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "$0")/../.." && pwd)"
cd "$ROOT_DIR"
[[ -f .env ]] || { echo "Run ./bootstrap.sh first." >&2; exit 1; }

if ! docker info >/dev/null 2>&1; then
  if [[ "$(uname -s)" == "Darwin" ]] && [[ -d /Applications/Docker.app ]]; then
    echo "Starting Docker Desktop..."
    open -gja Docker
    for _ in {1..60}; do
      docker info >/dev/null 2>&1 && break
      sleep 2
    done
  fi
fi

docker info >/dev/null 2>&1 || { echo "Docker Desktop/Engine is not ready. Start it, then run this script again." >&2; exit 1; }

docker compose --env-file .env up -d plex radarr sonarr prowlarr sabnzbd seerr

qbittorrent_ready=0
if [[ "${MOVIENOOK_CONTINUE_WITHOUT_VPN:-0}" == 1 ]]; then
  docker compose --env-file .env stop qbittorrent >/dev/null 2>&1 || true
  echo 'MovieNook is continuing without a VPN; qBittorrent remains stopped.' >&2
elif /bin/bash "$ROOT_DIR/scripts/portable/check-vpn.sh"; then
  docker compose --env-file .env up -d qbittorrent
  if /bin/bash "$ROOT_DIR/scripts/portable/check-vpn.sh" --verify-qbittorrent; then
    qbittorrent_ready=1
  else
    docker compose --env-file .env stop qbittorrent >/dev/null 2>&1 || true
    echo 'MovieNook disabled qBittorrent because its VPN egress could not be verified; all other services remain available.' >&2
  fi
else
  docker compose --env-file .env stop qbittorrent >/dev/null 2>&1 || true
  echo 'MovieNook disabled qBittorrent because no VPN owns the public route; all other services remain available.' >&2
fi
set -a
source "$ROOT_DIR/.env"
set +a

wait_for_url() {
  local name="$1" url="$2" accepted="$3" code
  printf 'Waiting for %s' "$name"
  for _ in {1..60}; do
    code="$(curl -L -sS -o /dev/null -w '%{http_code}' --max-time 3 "$url" || true)"
    if [[ " $accepted " == *" $code "* ]]; then
      printf ' ready\n'
      return 0
    fi
    printf '.'
    sleep 2
  done
  printf ' not ready yet\n'
  return 1
}

wait_for_url "Plex" "http://127.0.0.1:${PLEX_PORT}/identity" "200" || true
wait_for_url "Radarr" "http://127.0.0.1:${RADARR_PORT}/" "200" || true
wait_for_url "Sonarr" "http://127.0.0.1:${SONARR_PORT}/" "200" || true
wait_for_url "Prowlarr" "http://127.0.0.1:${PROWLARR_PORT}/" "200" || true
if (( qbittorrent_ready == 1 )); then
  wait_for_url "qBittorrent" "http://127.0.0.1:${QBITTORRENT_WEBUI_PORT}/" "200 401" || true
fi
wait_for_url "SABnzbd" "http://127.0.0.1:${SABNZBD_PORT}/" "200" || true
wait_for_url "Seerr" "http://127.0.0.1:${SEERR_PORT}/" "200" || true
/bin/bash "$ROOT_DIR/scripts/portable/status-movienook.sh"

if [[ "${1:-}" == "--open" ]]; then
  seerr_url="http://127.0.0.1:${SEERR_PORT}"
  plex_url="https://app.plex.tv/desktop/"
  case "$(uname -s)" in
    Darwin) open "$seerr_url" "$plex_url" ;;
    Linux) command -v xdg-open >/dev/null 2>&1 && xdg-open "$seerr_url" && xdg-open "$plex_url" ;;
  esac
fi
