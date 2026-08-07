#!/usr/bin/env bash
# Stops only containers named by this project's Compose file; it never removes data.
set -euo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "$0")/../.." && pwd)"
cd "$ROOT_DIR"
[[ -f .env ]] || { echo "Not bootstrapped: .env is missing."; exit 1; }
docker compose --env-file .env stop
