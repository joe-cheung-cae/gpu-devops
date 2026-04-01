#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck disable=SC1091
source "${ROOT_DIR}/scripts/image-bundle-common.sh"
# shellcheck disable=SC1091
source "${ROOT_DIR}/scripts/progress-common.sh"

ENV_FILE="${ROOT_DIR}/.env"
PLATFORM=""
DEPS_CSV="chrono,hdf5,h5engine,muparserx"

usage() {
  cat <<'EOF'
Usage: scripts/prepare-builder-deps.sh [--env-file PATH] [--platform centos7|rocky8|ubuntu2204] [--deps chrono,hdf5,h5engine,muparserx]

Prepares the project-local dependency cache used by docker compose and shell-runner Linux jobs.
EOF
}

while [[ $# -gt 0 ]]; do
  case "${1}" in
    --env-file)
      ENV_FILE="${2:?Missing value for --env-file}"
      shift 2
      ;;
    --platform)
      PLATFORM="${2:?Missing value for --platform}"
      shift 2
      ;;
    --deps)
      DEPS_CSV="${2:?Missing value for --deps}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: ${1}" >&2
      usage >&2
      exit 1
      ;;
  esac
done

normalize_host_path() {
  local env_base_dir="$1"
  local path="$2"

  if [[ "${path}" = /* ]]; then
    printf '%s\n' "${path}"
  else
    (cd "${env_base_dir}" && cd "${path}" && pwd)
  fi
}

validate_dep_name() {
  case "$1" in
    chrono|hdf5|h5engine|muparserx)
      ;;
    *)
      echo "Unsupported dependency: $1" >&2
      echo "Expected one of: chrono,hdf5,h5engine,muparserx" >&2
      exit 1
      ;;
  esac
}

progress_init 5
progress_step "Loading environment"
load_image_bundle_env "${ROOT_DIR}" "${ENV_FILE}"
require_export_image_bundle_env

PLATFORM="${PLATFORM:-${BUILDER_DEFAULT_PLATFORM}}"
if ! builder_platform_supported "${PLATFORM}"; then
  echo "Unsupported platform: ${PLATFORM}" >&2
  exit 1
fi

ENV_BASE_DIR="$(cd "$(dirname "${ENV_FILE}")" && pwd)"
HOST_PROJECT_DIR_VALUE="${HOST_PROJECT_DIR:-.}"
HOST_PROJECT_DIR="$(normalize_host_path "${ENV_BASE_DIR}" "${HOST_PROJECT_DIR_VALUE}")"
CUDA_CXX_DEPS_ROOT="${CUDA_CXX_DEPS_ROOT:-./artifacts/deps}"

if [[ "${CUDA_CXX_DEPS_ROOT}" = /* ]]; then
  HOST_DEPS_ROOT="${CUDA_CXX_DEPS_ROOT}"
  CONTAINER_DEPS_ROOT="${CUDA_CXX_DEPS_ROOT}"
  EXTRA_MOUNT=(-v "${HOST_DEPS_ROOT}:${CONTAINER_DEPS_ROOT}")
else
  HOST_DEPS_ROOT="${HOST_PROJECT_DIR}/${CUDA_CXX_DEPS_ROOT}"
  CONTAINER_DEPS_ROOT="/workspace/${CUDA_CXX_DEPS_ROOT}"
  EXTRA_MOUNT=()
fi
CONTAINER_PLATFORM_DEPS_ROOT="${CONTAINER_DEPS_ROOT}/${PLATFORM}"

mkdir -p "${HOST_DEPS_ROOT}/${PLATFORM}"

progress_step "Resolving builder image"
BUILDER_IMAGE="$(builder_image_for_platform "${PLATFORM}")"

IFS=',' read -r -a REQUESTED_DEPS <<< "${DEPS_CSV}"
DEPS=()
for dep in "${REQUESTED_DEPS[@]}"; do
  dep="${dep//[[:space:]]/}"
  [[ -n "${dep}" ]] || continue
  validate_dep_name "${dep}"
  DEPS+=("${dep}")
done

if [[ "${#DEPS[@]}" -eq 0 ]]; then
  echo "No dependencies selected. Use --deps chrono,hdf5,h5engine,muparserx" >&2
  exit 1
fi

progress_step "Preparing dependency command"
COMMANDS=()
for dep in "${DEPS[@]}"; do
  case "${dep}" in
    chrono)
      COMMANDS+=("DEPS_ROOT='${CONTAINER_PLATFORM_DEPS_ROOT}' CHRONO_ARCHIVE='/toolkit/docker/cuda-builder/deps/chrono-source.tar.gz' /toolkit/docker/cuda-builder/install-chrono.sh")
      ;;
    hdf5)
      COMMANDS+=("DEPS_ROOT='${CONTAINER_PLATFORM_DEPS_ROOT}' HDF5_ARCHIVE='/toolkit/docker/cuda-builder/deps/CMake-hdf5-1.14.1-2.tar.gz' /toolkit/docker/cuda-builder/install-hdf5.sh")
      ;;
    h5engine)
      COMMANDS+=("DEPS_ROOT='${CONTAINER_PLATFORM_DEPS_ROOT}' HDF5_INSTALL_PREFIX='${CONTAINER_PLATFORM_DEPS_ROOT}/hdf5-install' H5ENGINE_SPH_ARCHIVE='/toolkit/docker/cuda-builder/deps/h5engine-sph.tar.gz' H5ENGINE_DEM_ARCHIVE='/toolkit/docker/cuda-builder/deps/h5engine-dem.tar.gz' /toolkit/docker/cuda-builder/install-h5engine.sh")
      ;;
    muparserx)
      COMMANDS+=("DEPS_ROOT='${CONTAINER_PLATFORM_DEPS_ROOT}' /toolkit/docker/cuda-builder/install-muparserx.sh")
      ;;
  esac
done

COMMAND_STRING="$(printf '%s && ' "${COMMANDS[@]}")"
COMMAND_STRING="${COMMAND_STRING% && }"

progress_step "Preparing builder dependency cache"
docker run --rm \
  -v "${HOST_PROJECT_DIR}:/workspace" \
  -v "${ROOT_DIR}:/toolkit" \
  "${EXTRA_MOUNT[@]}" \
  -w /workspace \
  -e "BUILD_PLATFORM=${PLATFORM}" \
  -e "CUDA_CXX_DEPS_ROOT=${CUDA_CXX_DEPS_ROOT}" \
  -e "DEPS_ROOT=${CONTAINER_PLATFORM_DEPS_ROOT}" \
  -e "CHRONO_ARCHIVE=/toolkit/docker/cuda-builder/deps/chrono-source.tar.gz" \
  "${BUILDER_IMAGE}" \
  /bin/bash -lc "${COMMAND_STRING}"

progress_done "Prepared builder dependency cache"
progress_note "Platform: ${PLATFORM}"
progress_note "Builder image: ${BUILDER_IMAGE}"
progress_note "Dependency cache root: ${HOST_DEPS_ROOT}/${PLATFORM}"
progress_note "Dependencies: $(IFS=,; printf '%s' "${DEPS[*]}")"
