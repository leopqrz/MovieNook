#!/usr/bin/env bash
# Interactive VPN selector used by the Linux, Windows, and terminal launchers.
# It lists only supported clients detected on the current computer.
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "$0")/../.." && pwd)"
labels=()
providers=()
launchers=()

add_option() {
  labels+=("$1")
  providers+=("$2")
  launchers+=("$3")
}

case "$(uname -s)" in
  Darwin)
    [[ -d /Applications/NordVPN.app ]] && add_option 'NordVPN' 'nordvpn' '/Applications/NordVPN.app'
    [[ -d "$HOME/Applications/NordVPN.app" ]] && add_option 'NordVPN' 'nordvpn' "$HOME/Applications/NordVPN.app"
    [[ -d /Applications/ProtonVPN.app ]] && add_option 'Proton VPN' 'protonvpn' '/Applications/ProtonVPN.app'
    [[ -d "$HOME/Applications/ProtonVPN.app" ]] && add_option 'Proton VPN' 'protonvpn' "$HOME/Applications/ProtonVPN.app"
    ;;
  Linux)
    for command_name in proton-vpn-gtk-app proton-vpn-app protonvpn-app; do
      if command -v "$command_name" >/dev/null 2>&1; then
        add_option 'Proton VPN' 'protonvpn' "command:$command_name"
        break
      fi
    done
    if (( ${#providers[@]} == 0 )) && command -v flatpak >/dev/null 2>&1 && \
      flatpak info com.protonvpn.www >/dev/null 2>&1; then
      add_option 'Proton VPN' 'protonvpn' 'flatpak:com.protonvpn.www'
    fi
    if command -v nordvpn-gui >/dev/null 2>&1; then
      add_option 'NordVPN' 'nordvpn' 'command:nordvpn-gui'
    elif command -v nordvpn >/dev/null 2>&1; then
      add_option 'NordVPN' 'nordvpn' 'command:nordvpn'
    fi
    ;;
  MINGW*|MSYS*|CYGWIN*)
    proton_app_id="$(powershell.exe -NoProfile -NonInteractive -Command '(Get-StartApps | Where-Object { $_.Name -match "Proton.?VPN" } | Select-Object -First 1 -ExpandProperty AppID)' 2>/dev/null | tr -d '\r' || true)"
    nord_app_id="$(powershell.exe -NoProfile -NonInteractive -Command '(Get-StartApps | Where-Object { $_.Name -match "NordVPN" } | Select-Object -First 1 -ExpandProperty AppID)' 2>/dev/null | tr -d '\r' || true)"
    [[ -n "$proton_app_id" ]] && add_option 'Proton VPN' 'protonvpn' "windows:$proton_app_id"
    [[ -n "$nord_app_id" ]] && add_option 'NordVPN' 'nordvpn' "windows:$nord_app_id"
    ;;
esac

echo 'No supported VPN currently owns the public route.'
echo 'Choose an installed VPN to open, connect another VPN manually, or explicitly continue without one:'
for index in "${!labels[@]}"; do
  printf '  %d) %s\n' "$((index + 1))" "${labels[$index]}"
done
manual_number="$((${#labels[@]} + 1))"
continue_number="$((manual_number + 1))"
quit_number="$((continue_number + 1))"
printf '  %d) Connect Another VPN Manually\n' "$manual_number"
printf '  %d) Continue Without VPN\n' "$continue_number"
printf '  %d) Quit MovieNook\n' "$quit_number"
printf 'Selection: '
IFS= read -r selection

if [[ "$selection" == "$manual_number" ]]; then
  MOVIENOOK_VPN_PROVIDER=custom MOVIENOOK_VPN_AUTH_METHOD=native_app \
    /bin/bash "$ROOT_DIR/scripts/portable/sync-credentials.sh" >/dev/null 2>&1 || true
  echo 'Open and connect your VPN. MovieNook will continue when it owns the public route.'
  exit 10
fi
if [[ "$selection" == "$continue_number" ]]; then
  exit 0
fi
if [[ "$selection" == "$quit_number" || -z "$selection" ]]; then
  exit 11
fi
if [[ ! "$selection" =~ ^[0-9]+$ ]] || (( selection < 1 || selection > ${#labels[@]} )); then
  echo 'Invalid selection. MovieNook stopped.' >&2
  exit 11
fi

selected_index="$((selection - 1))"
provider="${providers[$selected_index]}"
launcher="${launchers[$selected_index]}"
MOVIENOOK_VPN_PROVIDER="$provider" MOVIENOOK_VPN_AUTH_METHOD=native_app \
  /bin/bash "$ROOT_DIR/scripts/portable/sync-credentials.sh" >/dev/null 2>&1 || true

case "$launcher" in
  command:nordvpn)
    nordvpn login
    ;;
  command:*)
    command_name="${launcher#command:}"
    nohup "$command_name" >/dev/null 2>&1 &
    ;;
  flatpak:*)
    flatpak run "${launcher#flatpak:}" >/dev/null 2>&1 &
    ;;
  windows:*)
    MOVIENOOK_VPN_APP_ID="${launcher#windows:}" powershell.exe -NoProfile -NonInteractive -Command \
      'Start-Process explorer.exe ("shell:AppsFolder\" + $env:MOVIENOOK_VPN_APP_ID)'
    ;;
  *)
    open "$launcher"
    ;;
esac

echo "Opened ${labels[$selected_index]}. Sign in and connect; MovieNook will continue automatically."
exit 10
