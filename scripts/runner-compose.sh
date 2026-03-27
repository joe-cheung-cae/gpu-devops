#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck disable=SC1091
source "${ROOT_DIR}/scripts/progress-common.sh"

if docker compose version >/dev/null 2>&1; then
  progress_init 2
  progress_step "Selecting docker compose implementation"
  progress_done "Executing runner compose command"
  exec docker compose -f "${ROOT_DIR}/runner-compose.yml" "$@"
fi

if command -v docker-compose >/dev/null 2>&1; then
  progress_init 2
  progress_step "Selecting docker-compose implementation"
  progress_done "Executing runner compose command"
  exec docker-compose -f "${ROOT_DIR}/runner-compose.yml" "$@"
fi

echo "Neither 'docker compose' nor 'docker-compose' is available. Install a Compose implementation first." >&2
exit 1
