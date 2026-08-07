#!/usr/bin/env bash
# Portable terminal launcher. Windows invokes it through MovieNook.cmd and Git Bash.
set -euo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
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
  echo 'MovieNook service configuration needs attention; opening Plex and Seerr because both interfaces are already available.' >&2
fi
set -a
. "$ROOT_DIR/.env"
set +a
case "$(uname -s)" in
  Darwin) open "http://127.0.0.1:${SEERR_PORT}" "https://app.plex.tv/desktop/" ;;
  Linux)
    xdg-open "http://127.0.0.1:${SEERR_PORT}" >/dev/null 2>&1 || true
    xdg-open "https://app.plex.tv/desktop/" >/dev/null 2>&1 || true
    ;;
  MINGW*|MSYS*|CYGWIN*)
    cmd.exe /c start '""' "http://127.0.0.1:${SEERR_PORT}" >/dev/null 2>&1
    cmd.exe /c start '""' "https://app.plex.tv/desktop/" >/dev/null 2>&1
    ;;
esac
