#!/usr/bin/env bash
# Idempotently wire MovieNook services using locally discovered settings.
# Secrets are passed to one short-lived container process and never printed.
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "$0")/../.." && pwd)"
PLEX_PREFERENCES="$ROOT_DIR/config/plex/Library/Application Support/Plex Media Server/Preferences.xml"
SEERR_SETTINGS="$ROOT_DIR/config/seerr/settings.json"
CREDENTIALS_FILE="$ROOT_DIR/private/credentials.env"
CONFIGURATOR="$ROOT_DIR/scripts/portable/configure-services.js"

read_xml_value() {
  local file="$1" element="$2"
  sed -nE "s:.*<${element}>([^<]+)</${element}>.*:\1:p" "$file" | head -n 1
}

read_json_string() {
  local file="$1" key="$2"
  sed -nE "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\"([^\"]+)\".*/\1/p" "$file" | head -n 1
}

for required in "$PLEX_PREFERENCES" "$SEERR_SETTINGS" "$CREDENTIALS_FILE" "$CONFIGURATOR"; do
  [[ -f "$required" ]] || { echo "MovieNook configuration input is missing: ${required#$ROOT_DIR/}" >&2; exit 1; }
done

plex_token="$(sed -nE 's/.*PlexOnlineToken="([^"]+)".*/\1/p' "$PLEX_PREFERENCES" | head -n 1)"
radarr_key="$(read_xml_value "$ROOT_DIR/config/radarr/config.xml" ApiKey)"
sonarr_key="$(read_xml_value "$ROOT_DIR/config/sonarr/config.xml" ApiKey)"
prowlarr_key="$(read_xml_value "$ROOT_DIR/config/prowlarr/config.xml" ApiKey)"
seerr_key="$(read_json_string "$SEERR_SETTINGS" apiKey)"

if [[ -z "$plex_token" || -z "$radarr_key" || -z "$sonarr_key" || -z "$prowlarr_key" || -z "$seerr_key" ]]; then
  echo "MovieNook is waiting for its local services to finish creating API credentials." >&2
  exit 1
fi

set -a
# This file is private, mode 600, and written using shell-safe values.
# shellcheck disable=SC1090
source "$CREDENTIALS_FILE"
set +a

export MOVIENOOK_PLEX_TOKEN="$plex_token"
export MOVIENOOK_RADARR_KEY="$radarr_key"
export MOVIENOOK_SONARR_KEY="$sonarr_key"
export MOVIENOOK_PROWLARR_KEY="$prowlarr_key"
export MOVIENOOK_SEERR_KEY="$seerr_key"
export MOVIENOOK_SABNZBD_KEY="${SABNZBD_API_KEY:-}"
export MOVIENOOK_SABNZBD_USERNAME="${SABNZBD_USERNAME:-}"
export MOVIENOOK_SABNZBD_PASSWORD="${SABNZBD_PASSWORD:-}"
export MOVIENOOK_QBITTORRENT_USERNAME="${QBITTORRENT_USERNAME:-}"
export MOVIENOOK_QBITTORRENT_PASSWORD="${QBITTORRENT_PASSWORD:-}"
export MOVIENOOK_USENET_PROVIDER_NAME="${USENET_PROVIDER_NAME:-}"
export MOVIENOOK_USENET_HOST="${USENET_HOST:-}"
export MOVIENOOK_USENET_PORT="${USENET_PORT:-}"
export MOVIENOOK_USENET_USE_SSL="${USENET_USE_SSL:-}"
export MOVIENOOK_USENET_USERNAME="${USENET_USERNAME:-}"
export MOVIENOOK_USENET_PASSWORD="${USENET_PASSWORD:-}"
export MOVIENOOK_INDEXER_1_NAME="${INDEXER_1_NAME:-}"
export MOVIENOOK_INDEXER_1_URL="${INDEXER_1_URL:-}"
export MOVIENOOK_INDEXER_1_API_KEY="${INDEXER_1_API_KEY:-}"
export MOVIENOOK_INDEXER_2_NAME="${INDEXER_2_NAME:-}"
export MOVIENOOK_INDEXER_2_URL="${INDEXER_2_URL:-}"
export MOVIENOOK_INDEXER_2_API_KEY="${INDEXER_2_API_KEY:-}"
plex_port="$(sed -nE 's/^PLEX_PORT=([0-9]+).*/\1/p' "$ROOT_DIR/.env" | head -n 1)"
export MOVIENOOK_PLEX_WEB_URL="http://127.0.0.1:${plex_port:-32400}/web"
export MOVIENOOK_QBITTORRENT_AVAILABLE=0
if docker ps --format '{{.Names}}' | grep -qx movienook-qbittorrent; then
  export MOVIENOOK_QBITTORRENT_AVAILABLE=1
fi

docker exec -i \
  -e MOVIENOOK_PLEX_TOKEN \
  -e MOVIENOOK_RADARR_KEY \
  -e MOVIENOOK_SONARR_KEY \
  -e MOVIENOOK_PROWLARR_KEY \
  -e MOVIENOOK_SEERR_KEY \
  -e MOVIENOOK_SABNZBD_KEY \
  -e MOVIENOOK_SABNZBD_USERNAME \
  -e MOVIENOOK_SABNZBD_PASSWORD \
  -e MOVIENOOK_QBITTORRENT_USERNAME \
  -e MOVIENOOK_QBITTORRENT_PASSWORD \
  -e MOVIENOOK_USENET_PROVIDER_NAME \
  -e MOVIENOOK_USENET_HOST \
  -e MOVIENOOK_USENET_PORT \
  -e MOVIENOOK_USENET_USE_SSL \
  -e MOVIENOOK_USENET_USERNAME \
  -e MOVIENOOK_USENET_PASSWORD \
  -e MOVIENOOK_INDEXER_1_NAME \
  -e MOVIENOOK_INDEXER_1_URL \
  -e MOVIENOOK_INDEXER_1_API_KEY \
  -e MOVIENOOK_INDEXER_2_NAME \
  -e MOVIENOOK_INDEXER_2_URL \
  -e MOVIENOOK_INDEXER_2_API_KEY \
  -e MOVIENOOK_QBITTORRENT_AVAILABLE \
  -e MOVIENOOK_PLEX_WEB_URL \
  movienook-seerr node < "$CONFIGURATOR"

unset plex_token radarr_key sonarr_key prowlarr_key seerr_key
unset MOVIENOOK_PLEX_TOKEN MOVIENOOK_RADARR_KEY MOVIENOOK_SONARR_KEY MOVIENOOK_PROWLARR_KEY MOVIENOOK_SEERR_KEY
unset MOVIENOOK_SABNZBD_KEY MOVIENOOK_SABNZBD_USERNAME MOVIENOOK_SABNZBD_PASSWORD
unset MOVIENOOK_QBITTORRENT_USERNAME MOVIENOOK_QBITTORRENT_PASSWORD MOVIENOOK_QBITTORRENT_AVAILABLE MOVIENOOK_PLEX_WEB_URL
unset MOVIENOOK_USENET_PROVIDER_NAME MOVIENOOK_USENET_HOST MOVIENOOK_USENET_PORT MOVIENOOK_USENET_USE_SSL
unset MOVIENOOK_USENET_USERNAME MOVIENOOK_USENET_PASSWORD
unset MOVIENOOK_INDEXER_1_NAME MOVIENOOK_INDEXER_1_URL MOVIENOOK_INDEXER_1_API_KEY
unset MOVIENOOK_INDEXER_2_NAME MOVIENOOK_INDEXER_2_URL MOVIENOOK_INDEXER_2_API_KEY
