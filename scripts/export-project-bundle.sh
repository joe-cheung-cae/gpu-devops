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
Usage: scripts/export-project-bundle.sh [--env-file PATH] [--output PATH]

Exports the configured images and integration assets into one portable bundle.
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
  ARCHIVE_PATH="$(default_project_bundle_path "${ROOT_DIR}")"
fi

mapfile -t IMAGES < <(collect_bundle_images)
mapfile -t ASSETS < <(project_bundle_assets)

STAGE_DIR="$(mktemp -d)"
trap 'rm -rf "${STAGE_DIR}"' EXIT

mkdir -p "${STAGE_DIR}/images" "${STAGE_DIR}/assets"

for image in "${IMAGES[@]}"; do
  if ! docker image inspect "${image}" >/dev/null 2>&1; then
    docker pull "${image}"
  fi
done

docker save "${IMAGES[@]}" | gzip -c > "${STAGE_DIR}/images/offline-images.tar.gz"
printf '%s\n' "${IMAGES[@]}" > "${STAGE_DIR}/images/offline-images.tar.gz.images.txt"

for asset in "${ASSETS[@]}"; do
  mkdir -p "${STAGE_DIR}/assets/$(dirname "${asset}")"
  cp "${ROOT_DIR}/${asset}" "${STAGE_DIR}/assets/${asset}"
done

cat > "${STAGE_DIR}/bundle-manifest.txt" <<EOF
bundle_type=project_integration
builder_image_family=${BUILDER_IMAGE_FAMILY}
builder_platforms=${BUILDER_PLATFORMS}
runner_docker_image=${RUNNER_DOCKER_IMAGE}
runner_service_image=${RUNNER_SERVICE_IMAGE}
assets_root=assets
images_archive=images/offline-images.tar.gz
EOF

mkdir -p "$(dirname "${ARCHIVE_PATH}")"
tar -czf "${ARCHIVE_PATH}" -C "${STAGE_DIR}" .

echo "Exported project integration bundle to ${ARCHIVE_PATH}"
echo "Bundle includes ${#IMAGES[@]} image(s) and ${#ASSETS[@]} asset file(s)"
