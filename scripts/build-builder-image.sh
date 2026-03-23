#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ -f "${ROOT_DIR}/.env" ]]; then
  # shellcheck disable=SC1091
  source "${ROOT_DIR}/.env"
fi

IMAGE="${BUILDER_IMAGE:-}"

if [[ -z "${IMAGE}" ]]; then
  echo "Set BUILDER_IMAGE in .env before building." >&2
  exit 1
fi

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

docker build \
  "${NETWORK_ARGS[@]}" \
  ${HTTP_PROXY_VALUE:+--build-arg "http_proxy=${HTTP_PROXY_VALUE}"} \
  ${HTTPS_PROXY_VALUE:+--build-arg "https_proxy=${HTTPS_PROXY_VALUE}"} \
  ${HTTP_PROXY_VALUE:+--build-arg "HTTP_PROXY=${HTTP_PROXY_VALUE}"} \
  ${HTTPS_PROXY_VALUE:+--build-arg "HTTPS_PROXY=${HTTPS_PROXY_VALUE}"} \
  ${NO_PROXY_VALUE:+--build-arg "no_proxy=${NO_PROXY_VALUE}"} \
  ${NO_PROXY_VALUE:+--build-arg "NO_PROXY=${NO_PROXY_VALUE}"} \
  -t "${IMAGE}" \
  -f "${ROOT_DIR}/docker/cuda-builder/Dockerfile" \
  "${ROOT_DIR}"
