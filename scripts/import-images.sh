#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck disable=SC1091
source "${ROOT_DIR}/scripts/image-bundle-common.sh"
# shellcheck disable=SC1091
source "${ROOT_DIR}/scripts/progress-common.sh"

ENV_FILE="${ROOT_DIR}/.env"
INPUT_OVERRIDE=""
SKIP_HASH_CHECK="false"

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
    --skip-hash-check)
      SKIP_HASH_CHECK="true"
      shift
      ;;
    -h|--help)
      cat <<'EOF'
Usage: scripts/import-images.sh [--env-file PATH] [--input PATH] [--skip-hash-check]

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

progress_init 4
progress_step "Loading environment"

load_image_bundle_env "${ROOT_DIR}" "${ENV_FILE}"

if [[ -n "${INPUT_OVERRIDE}" ]]; then
  ARCHIVE_PATH="$(resolve_bundle_path "${ROOT_DIR}" "${INPUT_OVERRIDE}")"
else
  ARCHIVE_PATH="$(default_archive_path "${ROOT_DIR}")"
fi

progress_step "Validating image archive input"
if [[ "${SKIP_HASH_CHECK}" != "true" ]]; then
  progress_note "SHA256 verification enabled"
else
  progress_note "SHA256 verification skipped by request"
fi
progress_step "Loading image archive into Docker"
import_image_archive "${ARCHIVE_PATH}" "${SKIP_HASH_CHECK}"

progress_done "Imported image bundle"
progress_note "Imported image bundle from ${ARCHIVE_PATH}"
