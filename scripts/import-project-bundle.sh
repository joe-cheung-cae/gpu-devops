#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck disable=SC1091
source "${ROOT_DIR}/scripts/image-bundle-common.sh"

ENV_FILE="${ROOT_DIR}/.env"
INPUT_OVERRIDE=""
TARGET_DIR=""
ASSETS_SUBDIR=".gpu-devops"
MODE="all"

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
    --target-dir)
      TARGET_DIR="${2:?Missing value for --target-dir}"
      shift 2
      ;;
    --assets-subdir)
      ASSETS_SUBDIR="${2:?Missing value for --assets-subdir}"
      shift 2
      ;;
    --mode)
      MODE="${2:?Missing value for --mode}"
      shift 2
      ;;
    -h|--help)
      cat <<'EOF'
Usage: scripts/import-project-bundle.sh [--target-dir PATH] [--env-file PATH] [--input PATH] [--assets-subdir DIR] [--mode all|images|assets]

Imports bundled images, integration assets, or both.
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

load_image_bundle_env "${ROOT_DIR}" "${ENV_FILE}"

if [[ -n "${INPUT_OVERRIDE}" ]]; then
  ARCHIVE_PATH="$(resolve_bundle_path "${ROOT_DIR}" "${INPUT_OVERRIDE}")"
else
  ARCHIVE_PATH="$(default_project_bundle_path "${ROOT_DIR}")"
fi

if [[ ! -f "${ARCHIVE_PATH}" ]]; then
  echo "Project bundle not found: ${ARCHIVE_PATH}" >&2
  exit 1
fi

STAGE_DIR="$(mktemp -d)"
trap 'rm -rf "${STAGE_DIR}"' EXIT

tar -xzf "${ARCHIVE_PATH}" -C "${STAGE_DIR}"

if [[ "${MODE}" == "all" || "${MODE}" == "images" ]]; then
  if [[ ! -f "${STAGE_DIR}/images/offline-images.tar.gz" ]]; then
    echo "Bundle is missing images/offline-images.tar.gz" >&2
    exit 1
  fi

  gzip -dc "${STAGE_DIR}/images/offline-images.tar.gz" | docker load
fi

if [[ "${MODE}" == "all" || "${MODE}" == "assets" ]]; then
  if [[ -z "${TARGET_DIR}" ]]; then
    echo "Set --target-dir to the destination project directory when importing assets." >&2
    exit 1
  fi
  if [[ ! -d "${STAGE_DIR}/assets" ]]; then
    echo "Bundle is missing assets/" >&2
    exit 1
  fi

  mkdir -p "$(dirname "${TARGET_DIR}")"
  TARGET_DIR="$(cd "$(dirname "${TARGET_DIR}")" && pwd)/$(basename "${TARGET_DIR}")"
  ASSETS_DEST="${TARGET_DIR}/${ASSETS_SUBDIR}"

  mkdir -p "${TARGET_DIR}" "${ASSETS_DEST}"
  cp -R "${STAGE_DIR}/assets/." "${ASSETS_DEST}/"

  cat > "${ASSETS_DEST}/.env" <<EOF
HOST_PROJECT_DIR=${TARGET_DIR}
CUDA_CXX_PROJECT_DIR=.
CUDA_CXX_BUILD_ROOT=${ASSETS_SUBDIR}/artifacts/cuda-cxx-build
CUDA_CXX_CMAKE_GENERATOR=Ninja
CUDA_CXX_CMAKE_ARGS=
CUDA_CXX_BUILD_ARGS=
EOF
fi

echo "Imported project bundle from ${ARCHIVE_PATH}"
echo "Bundle mode: ${MODE}"

if [[ "${MODE}" == "all" || "${MODE}" == "images" ]]; then
  echo "Imported bundled images into Docker"
fi

if [[ "${MODE}" == "all" || "${MODE}" == "assets" ]]; then
  echo "Installed integration assets to ${ASSETS_DEST}"
fi
