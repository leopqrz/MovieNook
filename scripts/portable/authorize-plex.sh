#!/usr/bin/env bash
# Uses Plex's browser authorization API, then claims this project's Plex server.
# Account tokens and claim codes remain in memory only and are never printed.
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "$0")/../.." && pwd)"
CLIENT_ID_FILE="$ROOT_DIR/private/plex-client-id"

set -a
# shellcheck disable=SC1091
. "$ROOT_DIR/.env"
set +a

mkdir -p "$ROOT_DIR/private"
chmod 700 "$ROOT_DIR/private"

if [[ ! -s "$CLIENT_ID_FILE" ]]; then
  umask 077
  client_id="movienook-$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')"
  printf '%s\n' "$client_id" > "$CLIENT_ID_FILE"
else
  IFS= read -r client_id < "$CLIENT_ID_FILE"
fi

pin_response="$(curl --fail --silent --show-error --request POST \
  --header 'Accept: application/json' \
  --header 'Origin: https://app.plex.tv' \
  --header 'X-Plex-Product: MovieNook' \
  --header 'X-Plex-Version: 1.0' \
  --header 'X-Plex-Platform: Docker' \
  --header 'X-Plex-Platform-Version: 1' \
  --header 'X-Plex-Device: Computer' \
  --header 'X-Plex-Device-Name: MovieNook' \
  --header "X-Plex-Client-Identifier: $client_id" \
  'https://plex.tv/api/v2/pins?strong=true')"

# The response also contains location.code (for example "CA"). Anchor these
# expressions at the top-level fields so that value is never mistaken for the PIN.
pin_id="$(printf '%s' "$pin_response" | sed -nE 's/^\{"id"[[:space:]]*:[[:space:]]*([0-9]+).*/\1/p')"
pin_code="$(printf '%s' "$pin_response" | sed -nE 's/^\{"id"[[:space:]]*:[[:space:]]*[0-9]+,[[:space:]]*"code"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p')"
unset pin_response

if [[ -z "$pin_id" || -z "$pin_code" ]]; then
  echo 'Plex did not create an authorization request.' >&2
  exit 2
fi

auth_url="https://app.plex.tv/auth/#!?clientID=$client_id&code=$pin_code&context%5Bdevice%5D%5Bproduct%5D=MovieNook&context%5Bdevice%5D%5Bversion%5D=1.0&context%5Bdevice%5D%5Bplatform%5D=Docker&context%5Bdevice%5D%5BplatformVersion%5D=1&context%5Bdevice%5D%5Bdevice%5D=Computer&context%5Bdevice%5D%5BdeviceName%5D=MovieNook"
case "$(uname -s)" in
  Darwin) open "$auth_url" ;;
  Linux)
    command -v xdg-open >/dev/null 2>&1 || {
      echo "Open this URL in a browser: $auth_url" >&2
      exit 3
    }
    xdg-open "$auth_url" >/dev/null 2>&1
    ;;
  MINGW*|MSYS*|CYGWIN*) cmd.exe /c start '""' "$auth_url" >/dev/null 2>&1 ;;
  *) echo "Open this URL in a browser: $auth_url" >&2; exit 3 ;;
esac
unset auth_url

auth_token=''
for _ in {1..240}; do
  pin_status="$(curl --fail --silent --show-error --get \
    --header 'Accept: application/json' \
    --header 'X-Plex-Product: MovieNook' \
    --header 'X-Plex-Version: 1.0' \
    --header 'X-Plex-Platform: Docker' \
    --header 'X-Plex-Platform-Version: 1' \
    --header 'X-Plex-Device: Computer' \
    --header 'X-Plex-Device-Name: MovieNook' \
    --header "X-Plex-Client-Identifier: $client_id" \
    "https://plex.tv/api/v2/pins/$pin_id")"
  auth_token="$(printf '%s' "$pin_status" | sed -nE 's/.*"authToken"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p')"
  unset pin_status
  [[ -n "$auth_token" ]] && break
  sleep 1
done
unset pin_id pin_code

if [[ -z "$auth_token" ]]; then
  echo 'Plex authorization was not completed within four minutes.' >&2
  exit 4
fi

# Exchange the short-lived browser authorization for a one-use server claim code.
claim_response="$(printf 'X-Plex-Token: %s\n' "$auth_token" | \
  curl --fail --silent --show-error --header @- --header 'Accept: application/json' \
  'https://plex.tv/api/claim/token.json')"
unset auth_token

claim_token="$(printf '%s' "$claim_response" | sed -nE 's/.*"token"[[:space:]]*:[[:space:]]*"(claim-[A-Za-z0-9_-]+)".*/\1/p')"
unset claim_response
if [[ -z "$claim_token" ]]; then
  echo 'Plex authorized MovieNook but did not issue a server claim code.' >&2
  exit 5
fi

if [[ ! "$claim_token" =~ ^claim-[A-Za-z0-9_-]+$ ]]; then
  echo 'Plex returned an invalid server claim code.' >&2
  exit 6
fi

preferences_file="$ROOT_DIR/config/plex/Library/Application Support/Plex Media Server/Preferences.xml"
cd "$ROOT_DIR"
PLEX_CLAIM="$claim_token" docker compose --env-file .env up -d --no-deps --force-recreate plex >/dev/null
unset claim_token PLEX_CLAIM client_id

for _ in {1..45}; do
  if [[ -f "$preferences_file" ]] && grep -Eq 'PlexOnlineToken="[^"]+"' "$preferences_file"; then
    echo 'Plex server claimed successfully.'
    exit 0
  fi
  sleep 2
done

echo 'Plex did not accept the claim code. It may have expired; authorize MovieNook again.' >&2
exit 7
