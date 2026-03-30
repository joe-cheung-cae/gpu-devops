#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck disable=SC1091
source "${ROOT_DIR}/scripts/progress-common.sh"

resolve_path() {
  local path="$1"
  if [[ "${path}" = /* ]]; then
    printf '%s\n' "${path}"
  else
    printf '%s\n' "${ROOT_DIR}/${path}"
  fi
}

gitlab_host() {
  local url="$1"
  url="${url#*://}"
  url="${url%%/*}"
  url="${url%%:*}"
  printf '%s\n' "${url}"
}

progress_init 4
progress_step "Loading runner configuration"

if [[ -f "${ROOT_DIR}/.env" ]]; then
  # shellcheck disable=SC1091
  source "${ROOT_DIR}/.env"
fi

: "${GITLAB_URL:?Set GITLAB_URL in .env}"
: "${RUNNER_REGISTRATION_TOKEN:?Set RUNNER_REGISTRATION_TOKEN in .env}"
: "${RUNNER_DOCKER_IMAGE:?Set RUNNER_DOCKER_IMAGE in .env}"
RUNNER_SERVICE_IMAGE="${RUNNER_SERVICE_IMAGE:-gitlab/gitlab-runner:alpine-v16.10.1}"
RUNNER_REGISTRATION_CONTAINER_NAME="${RUNNER_REGISTRATION_CONTAINER_NAME:-gitlab-runner-devops-register}"

MODE="${1:-gpu}"
progress_step "Resolving runner mode ${MODE}"

case "${MODE}" in
  gpu)
    DESCRIPTION="${RUNNER_DESCRIPTION_PREFIX:-shared-gpu}-gpu"
    TAGS="${RUNNER_TAG_LIST:-gpu,cuda,cuda-11}"
    LIMIT="${RUNNER_GPU_CONCURRENCY:-2}"
    ;;
  multi)
    DESCRIPTION="${RUNNER_DESCRIPTION_PREFIX:-shared-gpu}-multi"
    TAGS="${RUNNER_MULTI_TAG_LIST:-gpu-multi,cuda,cuda-11}"
    LIMIT="${RUNNER_MULTI_GPU_CONCURRENCY:-1}"
    ;;
  *)
    echo "Usage: $0 [gpu|multi]" >&2
    exit 1
    ;;
esac

progress_step "Preparing runner configuration directories"
mkdir -p "${ROOT_DIR}/runner/config" "${ROOT_DIR}/runner/cache"

TLS_CA_DOCKER_ARGS=()
TLS_CA_REGISTER_ARGS=()
if [[ -n "${RUNNER_TLS_CA_FILE:-}" ]]; then
  TLS_CA_SOURCE="$(resolve_path "${RUNNER_TLS_CA_FILE}")"
  if [[ ! -f "${TLS_CA_SOURCE}" ]]; then
    echo "Runner TLS CA file not found: ${TLS_CA_SOURCE}" >&2
    exit 1
  fi

  TLS_CA_HOSTNAME="$(gitlab_host "${GITLAB_URL}")"
  mkdir -p "${ROOT_DIR}/runner/config/certs"
  TLS_CA_TARGET_HOST_PATH="${ROOT_DIR}/runner/config/certs/${TLS_CA_HOSTNAME}.crt"
  cp "${TLS_CA_SOURCE}" "${TLS_CA_TARGET_HOST_PATH}"
  TLS_CA_CONTAINER_PATH="/etc/gitlab-runner/certs/${TLS_CA_HOSTNAME}.crt"
  TLS_CA_DOCKER_ARGS=(
    -v "${TLS_CA_TARGET_HOST_PATH}:${TLS_CA_CONTAINER_PATH}:ro"
  )
  TLS_CA_REGISTER_ARGS=(
    --tls-ca-file "${TLS_CA_CONTAINER_PATH}"
  )
fi

docker run --rm -it \
  --name "${RUNNER_REGISTRATION_CONTAINER_NAME}" \
  -v "${ROOT_DIR}/runner/config:/etc/gitlab-runner" \
  -v /var/run/docker.sock:/var/run/docker.sock \
  "${TLS_CA_DOCKER_ARGS[@]}" \
  "${RUNNER_SERVICE_IMAGE}" register \
  --non-interactive \
  "${TLS_CA_REGISTER_ARGS[@]}" \
  --url "${GITLAB_URL}" \
  --registration-token "${RUNNER_REGISTRATION_TOKEN}" \
  --executor "${RUNNER_EXECUTOR:-docker}" \
  --description "${DESCRIPTION}" \
  --docker-image "${RUNNER_DOCKER_IMAGE}" \
  --tag-list "${TAGS}" \
  --limit "${LIMIT}" \
  --locked="${RUNNER_LOCKED:-false}" \
  --run-untagged="${RUNNER_RUN_UNTAGGED:-false}" \
  --access-level "${RUNNER_ACCESS_LEVEL:-not_protected}" \
  --docker-runtime "nvidia" \
  --env "NVIDIA_VISIBLE_DEVICES=all" \
  --env "NVIDIA_DRIVER_CAPABILITIES=compute,utility" \
  --docker-volumes "/cache" \
  --docker-volumes "/var/run/docker.sock:/var/run/docker.sock"

progress_done "Runner registration command completed"
