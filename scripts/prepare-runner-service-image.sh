#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck disable=SC1091
source "${ROOT_DIR}/scripts/image-bundle-common.sh"
# shellcheck disable=SC1091
source "${ROOT_DIR}/scripts/progress-common.sh"

ENV_FILE="${ROOT_DIR}/.env"
MODE_OVERRIDE=""
SOURCE_OVERRIDE=""
TARGET_OVERRIDE=""

usage() {
  cat <<'EOF'
Usage: scripts/prepare-runner-service-image.sh [--env-file PATH] [--mode retag|build] [--source-image IMAGE] [--target-image IMAGE]

Prepares the Runner service image for online publishing and later offline import.
Default behavior pulls the upstream Runner image and retags it to RUNNER_SERVICE_IMAGE.
EOF
}

while [[ $# -gt 0 ]]; do
  case "${1}" in
    --env-file)
      ENV_FILE="${2:?Missing value for --env-file}"
      shift 2
      ;;
    --mode)
      MODE_OVERRIDE="${2:?Missing value for --mode}"
      shift 2
      ;;
    --source-image)
      SOURCE_OVERRIDE="${2:?Missing value for --source-image}"
      shift 2
      ;;
    --target-image)
      TARGET_OVERRIDE="${2:?Missing value for --target-image}"
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

progress_init 4
progress_step "Loading environment"
load_image_bundle_env "${ROOT_DIR}" "${ENV_FILE}"

case "${MODE_OVERRIDE:-${RUNNER_SERVICE_IMAGE_PREPARE_MODE}}" in
  retag|build)
    MODE="${MODE_OVERRIDE:-${RUNNER_SERVICE_IMAGE_PREPARE_MODE}}"
    ;;
  *)
    echo "Unsupported prepare mode: ${MODE_OVERRIDE:-${RUNNER_SERVICE_IMAGE_PREPARE_MODE}}" >&2
    echo "Expected one of: retag, build" >&2
    exit 1
    ;;
esac

SOURCE_IMAGE="${SOURCE_OVERRIDE:-${RUNNER_SERVICE_SOURCE_IMAGE}}"
TARGET_IMAGE="${TARGET_OVERRIDE:-${RUNNER_SERVICE_IMAGE}}"

if [[ -z "${TARGET_IMAGE}" ]]; then
  echo "RUNNER_SERVICE_IMAGE must be set in ${ENV_FILE} or via --target-image" >&2
  exit 1
fi

progress_step "Resolving runner service image source and target"
case "${MODE}" in
  retag)
    progress_step "Preparing runner service image via retag"
    docker pull "${SOURCE_IMAGE}"
    docker tag "${SOURCE_IMAGE}" "${TARGET_IMAGE}"
    ;;
  build)
    progress_step "Preparing runner service image via build"
    docker build \
      -t "${TARGET_IMAGE}" \
      --build-arg "RUNNER_SERVICE_SOURCE_IMAGE=${SOURCE_IMAGE}" \
      -f "${ROOT_DIR}/docker/gitlab-runner/Dockerfile" \
      "${ROOT_DIR}/docker/gitlab-runner"
    ;;
esac

progress_done "Verifying prepared runner service image"
docker image inspect "${TARGET_IMAGE}" >/dev/null

progress_note "Prepared Runner service image ${TARGET_IMAGE} via ${MODE} from ${SOURCE_IMAGE}"
