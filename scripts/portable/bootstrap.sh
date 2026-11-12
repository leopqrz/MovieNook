#!/usr/bin/env bash
# Creates only local directories and .env. It never writes credentials for you.
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "$0")/../.." && pwd)"
ENV_FILE="$ROOT_DIR/.env"
CREDENTIALS_FILE="$ROOT_DIR/private/credentials.env"

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker Desktop is required. Install it, start it, then re-run this script." >&2
  exit 1
fi

if [[ ! -f "$ENV_FILE" ]]; then
  root_for_docker="$ROOT_DIR"
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
      root_for_docker="$(cd "$ROOT_DIR" && pwd -W)"
      root_for_docker="${root_for_docker//\\//}"
      user_id=1000
      group_id=1000
      ;;
    *)
      user_id="$(id -u)"
      group_id="$(id -g)"
      ;;
  esac
  sed \
    -e "s|^MOVIENOOK_ROOT=.*|MOVIENOOK_ROOT=\"$root_for_docker\"|" \
    -e "s|^PUID=.*|PUID=$user_id|" \
    -e "s|^PGID=.*|PGID=$group_id|" \
    "$ROOT_DIR/.env.example" > "$ENV_FILE"
  chmod 600 "$ENV_FILE"
  echo "Created .env for this MovieNook folder."
fi

for dir in config/{plex,radarr,sonarr,prowlarr,qbittorrent,sabnzbd,seerr,janitor} media/{Movies,TV} downloads/{torrents,usenet}; do
  mkdir -p "$ROOT_DIR/$dir"
done

mkdir -p "$ROOT_DIR/private"
chmod 700 "$ROOT_DIR/private"
if [[ ! -f "$CREDENTIALS_FILE" ]]; then
  cp "$ROOT_DIR/credentials.env.example" "$CREDENTIALS_FILE"
  chmod 600 "$CREDENTIALS_FILE"
  echo "Created private/credentials.env. Add your local account details there."
fi

echo "Bootstrap complete. External provider credentials can be added to private/credentials.env."
