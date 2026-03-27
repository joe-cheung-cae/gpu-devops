#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck disable=SC1091
source "${ROOT_DIR}/scripts/progress-common.sh"

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

docker run --rm -it \
  --name "${RUNNER_REGISTRATION_CONTAINER_NAME}" \
  -v "${ROOT_DIR}/runner/config:/etc/gitlab-runner" \
  -v /var/run/docker.sock:/var/run/docker.sock \
  "${RUNNER_SERVICE_IMAGE}" register \
  --non-interactive \
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
