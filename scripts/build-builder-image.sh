#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env"
SELECTED_PLATFORM=""
BUILD_ALL=0
CUDA_VERSION_OVERRIDE=""

# shellcheck disable=SC1091
source "${ROOT_DIR}/scripts/common/env.sh"
# shellcheck disable=SC1091
source "${ROOT_DIR}/scripts/common/images.sh"
# shellcheck disable=SC1091
source "${ROOT_DIR}/scripts/common/progress.sh"

while [[ $# -gt 0 ]]; do
  case "${1}" in
    --env-file)
      ENV_FILE="${2:?Missing value for --env-file}"
      shift 2
      ;;
    --platform)
      SELECTED_PLATFORM="${2:?Missing value for --platform}"
      shift 2
      ;;
    --all-platforms)
      BUILD_ALL=1
      shift
      ;;
    --cuda-version)
      CUDA_VERSION_OVERRIDE="${2:?Missing value for --cuda-version}"
      shift 2
      ;;
    -h|--help)
      cat <<'EOF'
Usage: scripts/build-builder-image.sh [--env-file PATH] [--platform NAME | --all-platforms] [--cuda-version VERSION]

Build one builder image for the default or selected platform, or all supported platforms.
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

ORIGINAL_CUDA_VERSION="${BUILDER_CUDA_VERSION}"
if [[ -n "${CUDA_VERSION_OVERRIDE}" ]]; then
  BUILDER_CUDA_VERSION="${CUDA_VERSION_OVERRIDE}"
  ORIGINAL_TAG_SUFFIX="cuda${ORIGINAL_CUDA_VERSION}-cmake3.26"
  NEW_TAG_SUFFIX="cuda${BUILDER_CUDA_VERSION}-cmake3.26"

  if [[ "${BUILDER_IMAGE_FAMILY}" == *"${ORIGINAL_TAG_SUFFIX}"* ]]; then
    BUILDER_IMAGE_FAMILY="${BUILDER_IMAGE_FAMILY//${ORIGINAL_TAG_SUFFIX}/${NEW_TAG_SUFFIX}}"
  fi

  if [[ "${BUILDER_IMAGE}" == *"${ORIGINAL_TAG_SUFFIX}"* ]]; then
    BUILDER_IMAGE="${BUILDER_IMAGE//${ORIGINAL_TAG_SUFFIX}/${NEW_TAG_SUFFIX}}"
  fi
fi

progress_step "Resolving target platforms"

DOCKER_DAEMON_CONFIG="/etc/docker/daemon.json"
HTTP_PROXY_VALUE="${http_proxy:-${HTTP_PROXY:-}}"
HTTPS_PROXY_VALUE="${https_proxy:-${HTTPS_PROXY:-}}"
NO_PROXY_VALUE="${no_proxy:-${NO_PROXY:-}}"
NETWORK_ARGS=()

if [[ -f "${DOCKER_DAEMON_CONFIG}" ]]; then
  if [[ -z "${HTTP_PROXY_VALUE}" ]]; then
    HTTP_PROXY_VALUE="$(sed -n 's/.*"http-proxy"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "${DOCKER_DAEMON_CONFIG}" | head -n 1)"
  fi
  if [[ -z "${HTTPS_PROXY_VALUE}" ]]; then
    HTTPS_PROXY_VALUE="$(sed -n 's/.*"https-proxy"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "${DOCKER_DAEMON_CONFIG}" | head -n 1)"
  fi
  if [[ -z "${NO_PROXY_VALUE}" ]]; then
    NO_PROXY_VALUE="$(sed -n 's/.*"no-proxy"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "${DOCKER_DAEMON_CONFIG}" | head -n 1)"
  fi
fi

if [[ "${HTTP_PROXY_VALUE}" == http://127.0.0.1:* ]] || [[ "${HTTP_PROXY_VALUE}" == http://localhost:* ]] || \
   [[ "${HTTPS_PROXY_VALUE}" == http://127.0.0.1:* ]] || [[ "${HTTPS_PROXY_VALUE}" == http://localhost:* ]]; then
  NETWORK_ARGS=(--network host)
fi

platform_is_supported() {
  local platform="$1"
  local supported

  IFS=',' read -r -a supported <<< "${BUILDER_PLATFORMS}"
  for supported_platform in "${supported[@]}"; do
    if [[ "${supported_platform}" == "${platform}" ]]; then
      return 0
    fi
  done
  return 1
}

build_platform() {
  local platform="$1"
  local image dockerfile

  if ! platform_is_supported "${platform}"; then
    echo "Unsupported platform: ${platform}" >&2
    exit 1
  fi

  image="$(builder_image_for_platform "${platform}")"
  dockerfile="${ROOT_DIR}/docker/cuda-builder/${platform}.Dockerfile"

  if [[ ! -f "${dockerfile}" ]]; then
    echo "Missing Dockerfile for platform ${platform}: ${dockerfile}" >&2
    exit 1
  fi

  progress_note "[4/5] Building platform image ${platform}"
  docker build \
    "${NETWORK_ARGS[@]}" \
    --build-arg "CUDA_VERSION=${BUILDER_CUDA_VERSION}" \
    ${HTTP_PROXY_VALUE:+--build-arg "http_proxy=${HTTP_PROXY_VALUE}"} \
    ${HTTPS_PROXY_VALUE:+--build-arg "https_proxy=${HTTPS_PROXY_VALUE}"} \
    ${HTTP_PROXY_VALUE:+--build-arg "HTTP_PROXY=${HTTP_PROXY_VALUE}"} \
    ${HTTPS_PROXY_VALUE:+--build-arg "HTTPS_PROXY=${HTTPS_PROXY_VALUE}"} \
    ${NO_PROXY_VALUE:+--build-arg "no_proxy=${NO_PROXY_VALUE}"} \
    ${NO_PROXY_VALUE:+--build-arg "NO_PROXY=${NO_PROXY_VALUE}"} \
    -t "${image}" \
    -f "${dockerfile}" \
    "${ROOT_DIR}"
}

progress_step "Validating platform Dockerfiles"

if [[ "${BUILD_ALL}" -eq 1 ]]; then
  IFS=',' read -r -a supported_platforms <<< "${BUILDER_PLATFORMS}"
  for platform in "${supported_platforms[@]}"; do
    build_platform "${platform}"
  done
  progress_done "Completed builder image build workflow"
  exit 0
fi

if [[ -z "${SELECTED_PLATFORM}" ]]; then
  SELECTED_PLATFORM="${BUILDER_DEFAULT_PLATFORM}"
fi

build_platform "${SELECTED_PLATFORM}"
progress_done "Completed builder image build workflow"
