#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if docker compose version >/dev/null 2>&1; then
  exec docker compose -f "${ROOT_DIR}/runner-compose.yml" "$@"
fi

if command -v docker-compose >/dev/null 2>&1; then
  exec docker-compose -f "${ROOT_DIR}/runner-compose.yml" "$@"
fi

echo "Neither 'docker compose' nor 'docker-compose' is available. Install a Compose implementation first." >&2
exit 1
