#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ -f "${ROOT_DIR}/.env" ]]; then
  # shellcheck disable=SC1091
  source "${ROOT_DIR}/.env"
fi

IMAGE="${BUILDER_IMAGE:-}"

if [[ -z "${IMAGE}" ]]; then
  echo "Set BUILDER_IMAGE in .env before building." >&2
  exit 1
fi

docker build \
  -t "${IMAGE}" \
  -f "${ROOT_DIR}/docker/cuda-builder/Dockerfile" \
  "${ROOT_DIR}"
