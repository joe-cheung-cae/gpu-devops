#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env"

if [[ -f "${ENV_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
fi

HOST_PROJECT_DIR="${HOST_PROJECT_DIR:-${ROOT_DIR}}"
COMPOSE_ARGS=(-f "${ROOT_DIR}/docker-compose.yml")

if [[ -f "${ENV_FILE}" ]]; then
  COMPOSE_ARGS=(--env-file "${ENV_FILE}" "${COMPOSE_ARGS[@]}")
fi

if docker compose version >/dev/null 2>&1; then
  exec env HOST_PROJECT_DIR="${HOST_PROJECT_DIR}" docker compose "${COMPOSE_ARGS[@]}" "$@"
fi

if command -v docker-compose >/dev/null 2>&1; then
  exec env HOST_PROJECT_DIR="${HOST_PROJECT_DIR}" docker-compose "${COMPOSE_ARGS[@]}" "$@"
fi

echo "Neither 'docker compose' nor 'docker-compose' is available. Install a Compose implementation first." >&2
exit 1
