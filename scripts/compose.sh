#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env"
CUDA_CXX_ALLOW_ROOTFUL_DOCKER="${CUDA_CXX_ALLOW_ROOTFUL_DOCKER:-0}"

# shellcheck disable=SC1091
source "${ROOT_DIR}/scripts/common/progress.sh"
# shellcheck disable=SC1091
source "${ROOT_DIR}/scripts/common/docker-rootless-common.sh"

if [[ -f "${ENV_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
fi

HOST_PROJECT_DIR="${HOST_PROJECT_DIR:-${ROOT_DIR}}"
CUDA_CXX_RUN_UID="${CUDA_CXX_RUN_UID:-$(id -u)}"
CUDA_CXX_RUN_GID="${CUDA_CXX_RUN_GID:-$(id -g)}"
COMPOSE_ARGS=(-f "${ROOT_DIR}/docker-compose.yml")

require_rootless_docker

if [[ -f "${ENV_FILE}" ]]; then
  COMPOSE_ARGS=(--env-file "${ENV_FILE}" "${COMPOSE_ARGS[@]}")
fi

if docker compose version >/dev/null 2>&1; then
  progress_init 2
  progress_step "Selecting docker compose implementation"
  progress_done "Executing project compose command"
  exec env HOST_PROJECT_DIR="${HOST_PROJECT_DIR}" CUDA_CXX_RUN_UID="${CUDA_CXX_RUN_UID}" CUDA_CXX_RUN_GID="${CUDA_CXX_RUN_GID}" docker compose "${COMPOSE_ARGS[@]}" "$@"
fi

if command -v docker-compose >/dev/null 2>&1; then
  progress_init 2
  progress_step "Selecting docker-compose implementation"
  progress_done "Executing project compose command"
  exec env HOST_PROJECT_DIR="${HOST_PROJECT_DIR}" CUDA_CXX_RUN_UID="${CUDA_CXX_RUN_UID}" CUDA_CXX_RUN_GID="${CUDA_CXX_RUN_GID}" docker-compose "${COMPOSE_ARGS[@]}" "$@"
fi

echo "Neither 'docker compose' nor 'docker-compose' is available. Install a Compose implementation first." >&2
exit 1
