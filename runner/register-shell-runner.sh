#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck disable=SC1091
source "${ROOT_DIR}/scripts/common/progress.sh"

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
progress_step "Loading shell runner configuration"

if [[ -f "${ROOT_DIR}/.env" ]]; then
  # shellcheck disable=SC1091
  source "${ROOT_DIR}/.env"
fi

: "${GITLAB_URL:?Set GITLAB_URL in .env}"
: "${RUNNER_REGISTRATION_TOKEN:?Set RUNNER_REGISTRATION_TOKEN in .env}"

RUNNER_SHELL_USER="${RUNNER_SHELL_USER:-gitlab-runner}"

CURRENT_USER="$(id -un)"
if [[ "${CURRENT_USER}" != "${RUNNER_SHELL_USER}" ]]; then
  echo "Run this script as ${RUNNER_SHELL_USER}. Example: sudo -u ${RUNNER_SHELL_USER} -H ${BASH_SOURCE[0]} ${1:-gpu}" >&2
  exit 1
fi

MODE="${1:-gpu}"
progress_step "Resolving shell runner mode ${MODE}"

case "${MODE}" in
  gpu)
    DESCRIPTION="${RUNNER_DESCRIPTION_PREFIX:-shared-gpu}-gpu-shell"
    TAGS="${RUNNER_TAG_LIST:-gpu,cuda,cuda-11}"
    LIMIT="${RUNNER_GPU_CONCURRENCY:-2}"
    ;;
  multi)
    DESCRIPTION="${RUNNER_DESCRIPTION_PREFIX:-shared-gpu}-multi-shell"
    TAGS="${RUNNER_MULTI_TAG_LIST:-gpu-multi,cuda,cuda-11}"
    LIMIT="${RUNNER_MULTI_GPU_CONCURRENCY:-1}"
    ;;
  *)
    echo "Usage: $0 [gpu|multi]" >&2
    exit 1
    ;;
esac

progress_step "Preparing shell runner configuration directories"
SHELL_RUNNER_CONFIG_DIR="${HOME}/.gitlab-runner"
mkdir -p "${SHELL_RUNNER_CONFIG_DIR}"

TLS_CA_REGISTER_ARGS=()
if [[ -n "${RUNNER_TLS_CA_FILE:-}" ]]; then
  TLS_CA_SOURCE="$(resolve_path "${RUNNER_TLS_CA_FILE}")"
  if [[ ! -f "${TLS_CA_SOURCE}" ]]; then
    echo "Runner TLS CA file not found: ${TLS_CA_SOURCE}" >&2
    exit 1
  fi

  TLS_CA_HOSTNAME="$(gitlab_host "${GITLAB_URL}")"
  mkdir -p "${SHELL_RUNNER_CONFIG_DIR}/certs"
  TLS_CA_TARGET_PATH="${SHELL_RUNNER_CONFIG_DIR}/certs/${TLS_CA_HOSTNAME}.crt"
  cp "${TLS_CA_SOURCE}" "${TLS_CA_TARGET_PATH}"
  TLS_CA_REGISTER_ARGS=(
    --tls-ca-file "${TLS_CA_TARGET_PATH}"
  )
fi

gitlab-runner register \
  --non-interactive \
  "${TLS_CA_REGISTER_ARGS[@]}" \
  --url "${GITLAB_URL}" \
  --registration-token "${RUNNER_REGISTRATION_TOKEN}" \
  --executor shell \
  --description "${DESCRIPTION}" \
  --tag-list "${TAGS}" \
  --limit "${LIMIT}" \
  --locked="${RUNNER_LOCKED:-false}" \
  --run-untagged="${RUNNER_RUN_UNTAGGED:-false}" \
  --access-level "${RUNNER_ACCESS_LEVEL:-not_protected}"

progress_done "Shell runner registration command completed"
