#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck disable=SC1091
source "${ROOT_DIR}/scripts/image-bundle-common.sh"

ENV_FILE="${ROOT_DIR}/.env"
INPUT_OVERRIDE=""

while [[ $# -gt 0 ]]; do
  case "${1}" in
    --env-file)
      ENV_FILE="${2:?Missing value for --env-file}"
      shift 2
      ;;
    --input)
      INPUT_OVERRIDE="${2:?Missing value for --input}"
      shift 2
      ;;
    -h|--help)
      cat <<'EOF'
Usage: scripts/import-images.sh [--env-file PATH] [--input PATH]

Loads a compressed offline image bundle into the local Docker daemon.
EOF
      exit 0
      ;;
    *)
      echo "Unknown argument: ${1}" >&2
      exit 1
      ;;
  esac
done

load_image_bundle_env "${ROOT_DIR}" "${ENV_FILE}"

if [[ -n "${INPUT_OVERRIDE}" ]]; then
  ARCHIVE_PATH="$(resolve_bundle_path "${ROOT_DIR}" "${INPUT_OVERRIDE}")"
else
  ARCHIVE_PATH="$(default_archive_path "${ROOT_DIR}")"
fi

if [[ ! -f "${ARCHIVE_PATH}" ]]; then
  echo "Image archive not found: ${ARCHIVE_PATH}" >&2
  exit 1
fi

if [[ "${ARCHIVE_PATH}" == *.gz ]]; then
  gzip -dc "${ARCHIVE_PATH}" | docker load
else
  docker load -i "${ARCHIVE_PATH}"
fi

echo "Imported image bundle from ${ARCHIVE_PATH}"
