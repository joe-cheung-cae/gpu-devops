#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck disable=SC1091
source "${ROOT_DIR}/scripts/common/third-party-registry.sh"
# shellcheck disable=SC1091
source "${ROOT_DIR}/scripts/common/docker-rootless-common.sh"
# shellcheck disable=SC1091
source "${ROOT_DIR}/scripts/image-bundle-common.sh"
# shellcheck disable=SC1091
source "${ROOT_DIR}/scripts/progress-common.sh"

ENV_FILE="${ROOT_DIR}/.env"
PLATFORM=""
DEPS_CSV="$(third_party_all_deps_csv)"
CUDA_CXX_ALLOW_ROOTFUL_DOCKER="${CUDA_CXX_ALLOW_ROOTFUL_DOCKER:-0}"

usage() {
  cat <<'EOF'
Usage: scripts/prepare-builder-deps.sh [--env-file PATH] [--platform centos7|rocky8|ubuntu2204] [--deps chrono,eigen3,openmpi,hdf5,h5engine,muparserx]

Prepares the project-local dependency cache used by docker compose and shell-runner Linux jobs.
Linux project-side Docker workflows require rootless Docker by default. Set CUDA_CXX_ALLOW_ROOTFUL_DOCKER=1 only when you need to bypass this check for a legacy host.
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

progress_init 5
progress_step "Loading environment"
load_image_bundle_env "${ROOT_DIR}" "${ENV_FILE}"
require_export_image_bundle_env
require_rootless_docker

PLATFORM="${PLATFORM:-${BUILDER_DEFAULT_PLATFORM}}"
if ! builder_platform_supported "${PLATFORM}"; then
  echo "Unsupported platform: ${PLATFORM}" >&2
  exit 1
fi

ENV_BASE_DIR="$(cd "$(dirname "${ENV_FILE}")" && pwd)"
HOST_PROJECT_DIR_VALUE="${HOST_PROJECT_DIR:-.}"
HOST_PROJECT_DIR="$(normalize_host_path "${ENV_BASE_DIR}" "${HOST_PROJECT_DIR_VALUE}")"
CUDA_CXX_DEPS_ROOT="${CUDA_CXX_DEPS_ROOT:-./artifacts/deps}"
RUN_UID="${CUDA_CXX_RUN_UID:-$(id -u)}"
RUN_GID="${CUDA_CXX_RUN_GID:-$(id -g)}"
CONTAINER_HOME="/tmp/cuda-cxx-home"

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

RESOLVED_DEPS_CSV="$(third_party_resolve_dep_order "${DEPS_CSV}" linux)"
IFS=',' read -r -a DEPS <<< "${RESOLVED_DEPS_CSV}"

if [[ "${#DEPS[@]}" -eq 0 ]]; then
  echo "No dependencies selected. Use --deps chrono,eigen3,openmpi,hdf5,h5engine,muparserx" >&2
  exit 1
fi

progress_step "Preparing dependency command"
COMMANDS=()
for dep in "${DEPS[@]}"; do
  COMMANDS+=("$(third_party_linux_install_command "${dep}" "${CONTAINER_PLATFORM_DEPS_ROOT}")")
done

COMMAND_STRING="$(printf '%s && ' "${COMMANDS[@]}")"
COMMAND_STRING="${COMMAND_STRING% && }"
COMMAND_STRING="mkdir -p '${CONTAINER_HOME}/.ccache' && ${COMMAND_STRING}"

progress_step "Preparing builder dependency cache"
docker run --rm \
  --user "${RUN_UID}:${RUN_GID}" \
  -v "${HOST_PROJECT_DIR}:/workspace" \
  -v "${ROOT_DIR}:/toolkit" \
  "${EXTRA_MOUNT[@]}" \
  -w /workspace \
  -e "BUILD_PLATFORM=${PLATFORM}" \
  -e "CUDA_CXX_DEPS_ROOT=${CUDA_CXX_DEPS_ROOT}" \
  -e "DEPS_ROOT=${CONTAINER_PLATFORM_DEPS_ROOT}" \
  -e "HOME=${CONTAINER_HOME}" \
  -e "CCACHE_DIR=${CONTAINER_HOME}/.ccache" \
  -e "CHRONO_ARCHIVE=/toolkit/docker/cuda-builder/deps/chrono-source.tar.gz" \
  "${BUILDER_IMAGE}" \
  /bin/bash -lc "${COMMAND_STRING}"

progress_done "Prepared builder dependency cache"
progress_note "Platform: ${PLATFORM}"
progress_note "Builder image: ${BUILDER_IMAGE}"
progress_note "Dependency cache root: ${HOST_DEPS_ROOT}/${PLATFORM}"
progress_note "Dependencies: $(IFS=,; printf '%s' "${DEPS[*]}")"
