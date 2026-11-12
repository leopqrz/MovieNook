#!/usr/bin/env bash
# Portable terminal launcher. Windows invokes it through MovieNook.cmd and Git Bash.
set -euo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
# When this launch was asked for. The macOS app passes the moment it was clicked, which can be
# well before this script starts because the VPN chooser waits for an answer.
launch_requested_at="${MOVIENOOK_LAUNCH_REQUESTED_AT:-}"
[[ "$launch_requested_at" =~ ^[0-9]+$ ]] || launch_requested_at="$(date +%s)"
LOCK_DIR="$ROOT_DIR/private/start.lock"
mkdir -p "$ROOT_DIR/private"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  existing_pid="$(sed -n '1p' "$LOCK_DIR/pid" 2>/dev/null || true)"
  if [[ "$existing_pid" =~ ^[0-9]+$ ]] && kill -0 "$existing_pid" 2>/dev/null; then
    echo "MovieNook startup is already running."
    exit 0
  fi
  rm -f "$LOCK_DIR/pid"
  rmdir "$LOCK_DIR" 2>/dev/null || true
  mkdir "$LOCK_DIR"
fi
printf '%s\n' "$$" > "$LOCK_DIR/pid"
cleanup_lock() {
  rm -f "$LOCK_DIR/pid"
  rmdir "$LOCK_DIR" 2>/dev/null || true
}
trap cleanup_lock EXIT INT TERM

if ! /bin/bash "$ROOT_DIR/scripts/portable/check-vpn.sh"; then
  if [[ "${MOVIENOOK_WAIT_FOR_VPN:-0}" == 1 ]]; then
    echo 'Waiting up to two minutes for the selected VPN connection.'
    vpn_ready=0
    for _ in {1..60}; do
      if vpn_detail="$(/bin/bash "$ROOT_DIR/scripts/portable/check-vpn.sh" 2>&1)"; then
        echo "$vpn_detail"
        vpn_ready=1
        break
      fi
      sleep 2
    done
    if (( vpn_ready == 0 )); then
      echo 'VPN did not connect within two minutes. Starting the non-torrent services with qBittorrent disabled.' >&2
      export MOVIENOOK_CONTINUE_WITHOUT_VPN=1
    fi
  elif [[ -t 0 ]]; then
    set +e
    /bin/bash "$ROOT_DIR/scripts/portable/select-vpn.sh"
    vpn_selection_status=$?
    set -e
    case "$vpn_selection_status" in
      0) export MOVIENOOK_CONTINUE_WITHOUT_VPN=1 ;;
      10)
        echo 'Waiting up to two minutes for the VPN connection'
        vpn_ready=0
        for _ in {1..60}; do
          if vpn_detail="$(/bin/bash "$ROOT_DIR/scripts/portable/check-vpn.sh" 2>&1)"; then
            echo
            echo "$vpn_detail"
            vpn_ready=1
            break
          fi
          printf '.'
          sleep 2
        done
        if (( vpn_ready == 0 )); then
          echo
          echo 'VPN did not connect within two minutes. Starting the non-torrent services with qBittorrent disabled.' >&2
          export MOVIENOOK_CONTINUE_WITHOUT_VPN=1
        fi
        ;;
      11) exit 0 ;;
      *) echo 'MovieNook could not process the VPN selection.' >&2; exit "$vpn_selection_status" ;;
    esac
  elif [[ "${MOVIENOOK_CONTINUE_WITHOUT_VPN:-0}" != 1 ]]; then
    echo 'No VPN was detected. Starting the non-torrent services with qBittorrent disabled.' >&2
    export MOVIENOOK_CONTINUE_WITHOUT_VPN=1
  fi
fi
/bin/bash "$ROOT_DIR/scripts/portable/bootstrap.sh"
/bin/bash "$ROOT_DIR/scripts/portable/start-movienook.sh"

preferences="$ROOT_DIR/config/plex/Library/Application Support/Plex Media Server/Preferences.xml"
if ! grep -qE 'PlexOnlineToken="[^"]+' "$preferences" 2>/dev/null; then
  /bin/bash "$ROOT_DIR/scripts/portable/authorize-plex.sh"
fi

/bin/bash "$ROOT_DIR/scripts/portable/sync-credentials.sh"
set +e
/bin/bash "$ROOT_DIR/scripts/portable/configure-movienook.sh"
configuration_status=$?
set -e
if (( configuration_status != 0 )); then
  echo 'MovieNook service configuration needs attention; opening Plex because it is already available.' >&2
fi
set -a
. "$ROOT_DIR/.env"
set +a
# Open this server's own library: Plex's home page hides libraries that are not pinned to the sidebar.
plex_url="http://127.0.0.1:${PLEX_PORT}/web"
plex_machine="$(curl --fail --silent --max-time 5 "http://127.0.0.1:${PLEX_PORT}/identity" 2>/dev/null \
  | sed -nE 's/.*machineIdentifier="([^"]+)".*/\1/p' | head -n 1)" || true
if [[ -n "$plex_machine" ]]; then
  plex_url="${plex_url}/index.html#!/media/${plex_machine}/com.plexapp.plugins.library?source=1"
fi
# Only Plex is opened: titles are requested from Plex through the Watchlist, so Seerr works in
# the background. It stays available at http://127.0.0.1:${SEERR_PORT} for anyone who wants it.
#
# Clicking the launcher several times while it is still starting must not open a tab per click:
# a launch requested before Plex was last opened has already been answered by that tab.
open_stamp="$ROOT_DIR/private/last-plex-open"
last_opened_at="$(sed -n '1p' "$open_stamp" 2>/dev/null || true)"
if [[ "$last_opened_at" =~ ^[0-9]+$ ]] && (( launch_requested_at <= last_opened_at )); then
  echo 'Plex was already opened after this launch was requested; not opening another tab.'
else
  case "$(uname -s)" in
    Darwin) open "$plex_url" ;;
    Linux)
      xdg-open "$plex_url" >/dev/null 2>&1 || true
      ;;
    MINGW*|MSYS*|CYGWIN*)
      cmd.exe /c start '""' "$plex_url" >/dev/null 2>&1
      ;;
  esac
  date +%s > "$open_stamp"
fi
