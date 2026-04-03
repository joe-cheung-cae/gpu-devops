#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# shellcheck disable=SC1091
source "${ROOT_DIR}/scripts/common/env.sh"
# shellcheck disable=SC1091
source "${ROOT_DIR}/scripts/common/images.sh"
# shellcheck disable=SC1091
source "${ROOT_DIR}/scripts/common/archive.sh"
# shellcheck disable=SC1091
source "${ROOT_DIR}/scripts/common/progress.sh"

ENV_FILE="${ROOT_DIR}/.env"
OUTPUT_OVERRIDE=""
SELECTED_PLATFORM=""

timestamp_now() {
  date '+%Y-%m-%d %H:%M:%S %z'
}

epoch_now() {
  date '+%s'
}

image_size_bytes() {
  local image="$1"
  docker image inspect --format '{{.Size}}' "${image}"
}

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
    --platform)
      SELECTED_PLATFORM="${2:?Missing value for --platform}"
      shift 2
      ;;
    -h|--help)
      cat <<'EOF'
Usage: scripts/export/images.sh [--env-file PATH] [--output PATH]
                                 [--platform NAME]

Exports the configured builder images into a compressed offline bundle.
Use --platform to export one builder platform instead of the full matrix.
EOF
      exit 0
      ;;
    *)
      echo "Unknown argument: ${1}" >&2
      exit 1
      ;;
  esac
done

progress_init 5
progress_step "Loading environment"

load_image_bundle_env "${ROOT_DIR}" "${ENV_FILE}"
require_export_image_bundle_env

if [[ -n "${OUTPUT_OVERRIDE}" ]]; then
  ARCHIVE_PATH="$(resolve_bundle_path "${ROOT_DIR}" "${OUTPUT_OVERRIDE}")"
else
  ARCHIVE_PATH="$(default_archive_path "${ROOT_DIR}")"
fi

progress_step "Collecting image list"
if [[ -n "${SELECTED_PLATFORM}" ]]; then
  mapfile -t IMAGES < <(collect_build_images_for_platform "${SELECTED_PLATFORM}")
else
  mapfile -t IMAGES < <(collect_build_images)
fi

progress_step "Ensuring images are available locally"
ensure_bundle_images_available "${IMAGES[@]}"
index=0
for image in "${IMAGES[@]}"; do
  index=$((index + 1))
  start_time="$(timestamp_now)"
  progress_note "Starting [${index}/${#IMAGES[@]}] Preparing export for image ${image} at ${start_time}"
  image_size="$(image_size_bytes "${image}")"
  progress_note "  image size: ${image_size} bytes"
  end_time="$(timestamp_now)"
  progress_note "Finished [${index}/${#IMAGES[@]}] Preparing export for image ${image} at ${end_time}"
done
progress_step "Exporting image archive"
archive_start_time="$(timestamp_now)"
archive_start_epoch="$(epoch_now)"
progress_note "Starting archive export at ${archive_start_time}"
export_images_archive "${ARCHIVE_PATH}" "${IMAGES[@]}"
archive_end_time="$(timestamp_now)"
archive_end_epoch="$(epoch_now)"
progress_note "Finished archive export at ${archive_end_time}"
progress_note "Archive export elapsed: $((archive_end_epoch - archive_start_epoch))s"

progress_done "Exported image bundle"
progress_note "Exported ${#IMAGES[@]} image(s) to ${ARCHIVE_PATH}"
progress_note "Image list written to ${ARCHIVE_PATH}.images.txt"
