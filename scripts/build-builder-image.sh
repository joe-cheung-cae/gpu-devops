#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env"
SELECTED_PLATFORM=""
BUILD_ALL=0
NO_CACHE=0

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
    --no-cache)
      NO_CACHE=1
      shift
      ;;
    -h|--help)
      cat <<'EOF'
Usage: scripts/build-builder-image.sh [--env-file PATH] [--platform NAME | --all-platforms] [--no-cache]

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

if [[ -f "${ENV_FILE}" ]]; then
  # shellcheck disable=SC1091
  source "${ENV_FILE}"
fi

DEFAULT_PLATFORM="${BUILDER_DEFAULT_PLATFORM:-centos7}"
BUILDER_PLATFORMS="${BUILDER_PLATFORMS:-centos7,rocky8,ubuntu2204}"
BUILDER_IMAGE_FAMILY="${BUILDER_IMAGE_FAMILY:-}"

if [[ -z "${BUILDER_IMAGE_FAMILY}" ]] && [[ -n "${BUILDER_IMAGE:-}" ]]; then
  BUILDER_IMAGE_FAMILY="${BUILDER_IMAGE%-${DEFAULT_PLATFORM}}"
fi

if [[ -z "${BUILDER_IMAGE_FAMILY}" ]] && [[ -z "${BUILDER_IMAGE:-}" ]]; then
  echo "Set BUILDER_IMAGE_FAMILY or BUILDER_IMAGE in .env before building." >&2
  exit 1
fi

DOCKER_DAEMON_CONFIG="/etc/docker/daemon.json"
HTTP_PROXY_VALUE="${http_proxy:-${HTTP_PROXY:-}}"
HTTPS_PROXY_VALUE="${https_proxy:-${HTTPS_PROXY:-}}"
NO_PROXY_VALUE="${no_proxy:-${NO_PROXY:-}}"
NETWORK_ARGS=()
BUILD_ARGS=()

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

if [[ "${NO_CACHE}" -eq 1 ]]; then
  BUILD_ARGS+=(--no-cache)
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

image_for_platform() {
  local platform="$1"
  if [[ "${platform}" == "${DEFAULT_PLATFORM}" ]] && [[ -n "${BUILDER_IMAGE:-}" ]]; then
    printf '%s\n' "${BUILDER_IMAGE}"
    return 0
  fi
  printf '%s-%s\n' "${BUILDER_IMAGE_FAMILY}" "${platform}"
}

build_platform() {
  local platform="$1"
  local image dockerfile

  if ! platform_is_supported "${platform}"; then
    echo "Unsupported platform: ${platform}" >&2
    exit 1
  fi

  image="$(image_for_platform "${platform}")"
  dockerfile="${ROOT_DIR}/docker/cuda-builder/${platform}.Dockerfile"

  if [[ ! -f "${dockerfile}" ]]; then
    echo "Missing Dockerfile for platform ${platform}: ${dockerfile}" >&2
    exit 1
  fi

  docker build \
    "${NETWORK_ARGS[@]}" \
    "${BUILD_ARGS[@]}" \
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

if [[ "${BUILD_ALL}" -eq 1 ]]; then
  IFS=',' read -r -a supported_platforms <<< "${BUILDER_PLATFORMS}"
  for platform in "${supported_platforms[@]}"; do
    build_platform "${platform}"
  done
  exit 0
fi

if [[ -z "${SELECTED_PLATFORM}" ]]; then
  SELECTED_PLATFORM="${DEFAULT_PLATFORM}"
fi

build_platform "${SELECTED_PLATFORM}"
