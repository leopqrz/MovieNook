#!/usr/bin/env bash
# Check the public VPN route, and optionally verify qBittorrent uses the same
# public address. This is a startup safety gate, not a permanent kill switch.
set -euo pipefail

is_tunnel_name() {
  [[ "$1" =~ ^(utun|tun|tap|wg|proton|nord|nordlynx|windscribe|ppp)[A-Za-z0-9_.:-]*$ ]]
}

is_tailscale_address() {
  local first='' second=''
  IFS=. read -r first second _ <<<"$1"
  [[ "$first" == 100 && "$second" =~ ^[0-9]+$ && "$second" -ge 64 && "$second" -le 127 ]]
}

check_public_route() {
  local route_interface='' tunnel_ipv4='' line='' lower_line='' service_id='' service_interface='' provider=''
  case "$(uname -s)" in
    Darwin)
      route_interface="$(/sbin/route -n get 1.1.1.1 2>/dev/null | awk '/interface:/{print $2; exit}' || true)"
      [[ -n "$route_interface" ]] || return 1

      # Prefer a named macOS VPN service when one owns the actual public route.
      while IFS= read -r line; do
        [[ "$line" == *'(Connected)'* ]] || continue
        lower_line="$(printf '%s' "$line" | tr '[:upper:]' '[:lower:]')"
        [[ "$lower_line" == *tailscale* ]] && continue
        provider="$(printf '%s\n' "$line" | sed -nE 's/.*"([^"]+)"[[:space:]]*\[[^]]+\][[:space:]]*$/\1/p')"
        [[ -n "$provider" ]] || provider='VPN'
        service_id="$(printf '%s\n' "$line" | sed -nE 's/.*\(Connected\)[[:space:]]+([0-9A-Fa-f-]+).*/\1/p')"
        [[ -n "$service_id" ]] || continue
        service_interface="$(/usr/sbin/scutil --nc status "$service_id" 2>/dev/null | sed -nE 's/^[[:space:]]*InterfaceName[[:space:]]*:[[:space:]]*([^[:space:]]+).*/\1/p' | head -n 1)"
        if [[ -n "$service_interface" && "$service_interface" == "$route_interface" ]]; then
          echo "$provider owns the public route on $route_interface."
          return 0
        fi
      done < <(/usr/sbin/scutil --nc list 2>/dev/null || true)

      # Network Extension VPNs often do not appear as Connected in scutil --nc.
      # Accept any tunnel owning the public route, but exclude Tailscale CGNAT.
      if is_tunnel_name "$route_interface"; then
        tunnel_ipv4="$(/sbin/ifconfig "$route_interface" 2>/dev/null | awk '/^[[:space:]]*inet[[:space:]]/{print $2; exit}' || true)"
        if [[ "$route_interface" != tailscale* ]] && ! is_tailscale_address "$tunnel_ipv4"; then
          echo "A VPN tunnel owns the public route on $route_interface."
          return 0
        fi
      fi
      ;;
    Linux)
      route_interface="$(ip route get 1.1.1.1 2>/dev/null | sed -nE 's/.* dev ([^ ]+).*/\1/p' | head -n 1 || true)"
      if [[ -n "$route_interface" && "$route_interface" != tailscale* ]] && is_tunnel_name "$route_interface"; then
        echo "VPN route active on $route_interface."
        return 0
      fi
      if command -v nmcli >/dev/null 2>&1 && \
        nmcli -t -f NAME,TYPE connection show --active 2>/dev/null | \
        grep -Evi '^tailscale:' | grep -Eqi ':(vpn|wireguard)$'; then
        echo 'NetworkManager reports an active VPN.'
        return 0
      fi
      ;;
    MINGW*|MSYS*|CYGWIN*)
      if powershell.exe -NoProfile -NonInteractive -Command \
        '$vpn = Get-VpnConnection -ErrorAction SilentlyContinue | Where-Object { $_.ConnectionStatus -eq "Connected" -and $_.Name -notmatch "Tailscale" }; $adapters = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq "Up" -and ($_.Name + " " + $_.InterfaceDescription) -notmatch "Tailscale" -and ($_.Name + " " + $_.InterfaceDescription) -match "VPN|WireGuard|Wintun|TAP|OpenVPN|Mullvad|IVPN|Proton|Nord|Windscribe|Surfshark|ExpressVPN|TunnelBear|Private Internet Access|GlobalProtect|FortiClient" }; if ($vpn -or $adapters) { exit 0 } else { exit 1 }' \
        >/dev/null 2>&1; then
        echo 'Windows reports an active VPN adapter.'
        return 0
      fi
      ;;
  esac
  echo 'No supported VPN owns the public route.' >&2
  return 1
}

public_ip_from_host() {
  curl -4fsS --max-time 10 https://api.ipify.org 2>/dev/null || \
    curl -4fsS --max-time 10 https://ifconfig.me/ip 2>/dev/null
}

public_ip_from_qbittorrent() {
  docker exec movienook-qbittorrent sh -c \
    'wget -qO- -T 10 https://api.ipify.org 2>/dev/null || curl -4fsS --max-time 10 https://ifconfig.me/ip 2>/dev/null'
}

verify_qbittorrent_egress() {
  local host_ip='' container_ip=''
  check_public_route || return 1
  docker ps --format '{{.Names}}' | grep -qx movienook-qbittorrent || {
    echo 'qBittorrent is not running, so its VPN route cannot be verified.' >&2
    return 1
  }
  host_ip="$(public_ip_from_host || true)"
  container_ip="$(public_ip_from_qbittorrent 2>/dev/null || true)"
  if [[ -z "$host_ip" || -z "$container_ip" ]]; then
    echo 'Could not verify both public addresses; refusing to assume qBittorrent is protected.' >&2
    return 1
  fi
  if [[ "$host_ip" != "$container_ip" ]]; then
    echo 'qBittorrent does not use the VPN-routed public address.' >&2
    return 1
  fi
  echo 'qBittorrent currently uses the VPN-routed public address.'
}

case "${1:-}" in
  --verify-qbittorrent) verify_qbittorrent_egress ;;
  '') check_public_route ;;
  *) echo "Usage: $0 [--verify-qbittorrent]" >&2; exit 2 ;;
esac
