#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck disable=SC1091
source "${ROOT_DIR}/scripts/image-bundle-common.sh"

ENV_FILE="${ROOT_DIR}/.env"
OUTPUT_OVERRIDE=""

while [[ $# -gt 0 ]]; do
  case "${1}" in
    --env-file)
      ENV_FILE="${2:?Missing value for --env-file}"
      shift 2
      ;;
    --output)
      OUTPUT_OVERRIDE="${2:?Missing value for --output}"
      shift 2
      ;;
    -h|--help)
      cat <<'EOF'
Usage: scripts/export-images.sh [--env-file PATH] [--output PATH]

Exports the configured builder/runner images into a compressed offline bundle.
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
require_export_image_bundle_env

if [[ -n "${OUTPUT_OVERRIDE}" ]]; then
  ARCHIVE_PATH="$(resolve_bundle_path "${ROOT_DIR}" "${OUTPUT_OVERRIDE}")"
else
  ARCHIVE_PATH="$(default_archive_path "${ROOT_DIR}")"
fi

mapfile -t IMAGES < <(collect_bundle_images)

mkdir -p "$(dirname "${ARCHIVE_PATH}")"

for image in "${IMAGES[@]}"; do
  if ! docker image inspect "${image}" >/dev/null 2>&1; then
    docker pull "${image}"
  fi
done

docker save "${IMAGES[@]}" | gzip -c > "${ARCHIVE_PATH}"
printf '%s\n' "${IMAGES[@]}" > "${ARCHIVE_PATH}.images.txt"

echo "Exported ${#IMAGES[@]} image(s) to ${ARCHIVE_PATH}"
echo "Image list written to ${ARCHIVE_PATH}.images.txt"
