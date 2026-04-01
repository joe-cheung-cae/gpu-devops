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
source "${ROOT_DIR}/scripts/common/project-bundle.sh"
# shellcheck disable=SC1091
source "${ROOT_DIR}/scripts/common/progress.sh"

ENV_FILE="${ROOT_DIR}/.env"
OUTPUT_OVERRIDE=""
MODE="all"

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
    --mode)
      MODE="${2:?Missing value for --mode}"
      shift 2
      ;;
    -h|--help)
      cat <<'EOF'
Usage: scripts/export-project-bundle.sh [--env-file PATH] [--output PATH] [--mode all|images|assets]

Exports images, integration assets, or both into one portable bundle.
EOF
      exit 0
      ;;
    *)
      echo "Unknown argument: ${1}" >&2
      exit 1
      ;;
  esac
done

MODE="$(normalize_bundle_mode "${MODE}")"

progress_init 5
progress_step "Loading environment"
load_image_bundle_env "${ROOT_DIR}" "${ENV_FILE}"

if [[ -n "${OUTPUT_OVERRIDE}" ]]; then
  ARCHIVE_PATH="$(resolve_bundle_path "${ROOT_DIR}" "${OUTPUT_OVERRIDE}")"
else
  ARCHIVE_PATH="$(default_project_bundle_path "${ROOT_DIR}")"
fi

STAGE_DIR="$(mktemp -d)"
trap 'rm -rf "${STAGE_DIR}"' EXIT

mkdir -p "${STAGE_DIR}"

IMAGES=()
ASSETS=()

progress_step "Preparing bundled images"
if [[ "${MODE}" == "all" || "${MODE}" == "images" ]]; then
  require_export_image_bundle_env
  mapfile -t IMAGES < <(collect_bundle_images)
  mkdir -p "${STAGE_DIR}/images"
  ensure_bundle_images_available "${IMAGES[@]}"
  export_images_archive "${STAGE_DIR}/images/offline-images.tar.gz" "${IMAGES[@]}"
fi

progress_step "Preparing bundled assets"
if [[ "${MODE}" == "all" || "${MODE}" == "assets" ]]; then
  mapfile -t ASSETS < <(project_bundle_assets)
  mkdir -p "${STAGE_DIR}/assets"

  for asset in "${ASSETS[@]}"; do
    mkdir -p "${STAGE_DIR}/assets/$(dirname "${asset}")"
    if [[ -d "${ROOT_DIR}/${asset}" ]]; then
      cp -R "${ROOT_DIR}/${asset}" "${STAGE_DIR}/assets/${asset}"
    else
      cp "${ROOT_DIR}/${asset}" "${STAGE_DIR}/assets/${asset}"
    fi
  done
fi

cat > "${STAGE_DIR}/bundle-manifest.txt" <<EOF
bundle_type=project_integration
bundle_mode=${MODE}
builder_image_family=${BUILDER_IMAGE_FAMILY:-}
builder_platforms=${BUILDER_PLATFORMS:-}
runner_docker_image=${RUNNER_DOCKER_IMAGE:-}
runner_service_image=${RUNNER_SERVICE_IMAGE:-}
assets_root=$( [[ "${MODE}" == "all" || "${MODE}" == "assets" ]] && printf 'assets' )
images_archive=$( [[ "${MODE}" == "all" || "${MODE}" == "images" ]] && printf 'images/offline-images.tar.gz' )
EOF

progress_step "Creating portable bundle archive"
mkdir -p "$(dirname "${ARCHIVE_PATH}")"
tar -czf "${ARCHIVE_PATH}" -C "${STAGE_DIR}" .
write_bundle_sha256 "${ARCHIVE_PATH}"

progress_done "Exported project integration bundle"
progress_note "Exported project integration bundle to ${ARCHIVE_PATH}"
progress_note "Bundle mode: ${MODE}"
progress_note "Bundle includes ${#IMAGES[@]} image(s) and ${#ASSETS[@]} asset file(s)"
