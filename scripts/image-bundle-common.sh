#!/usr/bin/env bash

if [[ -n "${IMAGE_BUNDLE_COMMON_LOADED:-}" ]]; then
  return 0
fi
IMAGE_BUNDLE_COMMON_LOADED=1

load_image_bundle_env() {
  local root_dir="$1"
  local env_file="$2"

  if [[ ! -f "${env_file}" ]]; then
    echo "Environment file not found: ${env_file}" >&2
    exit 1
  fi

  # shellcheck disable=SC1090
  source "${env_file}"

  if [[ -z "${RUNNER_SERVICE_IMAGE:-}" ]]; then
    RUNNER_SERVICE_IMAGE="gitlab/gitlab-runner:alpine-v16.10.1"
  fi

  if [[ -z "${BUILDER_DEFAULT_PLATFORM:-}" ]]; then
    BUILDER_DEFAULT_PLATFORM="centos7"
  fi

  if [[ -z "${BUILDER_PLATFORMS:-}" ]]; then
    BUILDER_PLATFORMS="centos7,rocky8,ubuntu2204"
  fi

  if [[ -z "${IMAGE_ARCHIVE_PATH:-}" ]]; then
    IMAGE_ARCHIVE_PATH="${root_dir}/artifacts/offline-images.tar.gz"
  fi

  if [[ -z "${PROJECT_BUNDLE_PATH:-}" ]]; then
    PROJECT_BUNDLE_PATH="${root_dir}/artifacts/project-integration-bundle.tar.gz"
  fi
}

require_export_image_bundle_env() {
  if [[ -z "${BUILDER_IMAGE:-}" ]] && [[ -z "${BUILDER_IMAGE_FAMILY:-}" ]]; then
    echo "Set BUILDER_IMAGE or BUILDER_IMAGE_FAMILY in .env" >&2
    exit 1
  fi

  if [[ -z "${BUILDER_IMAGE_FAMILY:-}" ]] && [[ -n "${BUILDER_IMAGE:-}" ]]; then
    BUILDER_IMAGE_FAMILY="${BUILDER_IMAGE%-${BUILDER_DEFAULT_PLATFORM}}"
  fi

  if [[ -z "${BUILDER_IMAGE:-}" ]] && [[ -n "${BUILDER_IMAGE_FAMILY:-}" ]]; then
    BUILDER_IMAGE="${BUILDER_IMAGE_FAMILY}-${BUILDER_DEFAULT_PLATFORM}"
  fi

  if [[ -z "${RUNNER_DOCKER_IMAGE:-}" ]]; then
    RUNNER_DOCKER_IMAGE="${BUILDER_IMAGE}"
  fi
}

builder_export_images() {
  local image platform

  if [[ -n "${BUILDER_IMAGE_EXPORTS:-}" ]]; then
    IFS=',' read -r -a images <<< "${BUILDER_IMAGE_EXPORTS}"
    for image in "${images[@]}"; do
      [[ -n "${image}" ]] && printf '%s\n' "${image}"
    done
    return 0
  fi

  if [[ -n "${BUILDER_IMAGE_FAMILY:-}" ]]; then
    IFS=',' read -r -a platforms <<< "${BUILDER_PLATFORMS}"
    for platform in "${platforms[@]}"; do
      printf '%s-%s\n' "${BUILDER_IMAGE_FAMILY}" "${platform}"
    done
    return 0
  fi

  printf '%s\n' "${BUILDER_IMAGE}"
}

resolve_bundle_path() {
  local root_dir="$1"
  local path="$2"

  if [[ "${path}" = /* ]]; then
    printf '%s\n' "${path}"
  else
    printf '%s\n' "${root_dir}/${path}"
  fi
}

default_archive_path() {
  local root_dir="$1"
  resolve_bundle_path "${root_dir}" "${IMAGE_ARCHIVE_PATH}"
}

default_project_bundle_path() {
  local root_dir="$1"
  resolve_bundle_path "${root_dir}" "${PROJECT_BUNDLE_PATH}"
}

collect_bundle_images() {
  local image
  declare -A seen=()

  while IFS= read -r image; do
    [[ -n "${image}" ]] || continue
    if [[ -z "${seen["${image}"]+x}" ]]; then
      printf '%s\n' "${image}"
      seen["${image}"]=1
    fi
  done < <(builder_export_images)

  for image in "${RUNNER_DOCKER_IMAGE}" "${RUNNER_SERVICE_IMAGE}"; do
    [[ -n "${image}" ]] || continue
    if [[ -z "${seen["${image}"]+x}" ]]; then
      printf '%s\n' "${image}"
      seen["${image}"]=1
    fi
  done
}

project_bundle_assets() {
  cat <<'EOF'
.env.example
docker-compose.yml
runner-compose.yml
examples/gitlab-ci/shared-gpu-runner.yml
scripts/compose.sh
scripts/runner-compose.sh
docs/operations.md
docs/tutorial.en.md
docs/tutorial.zh-CN.md
EOF
}

normalize_bundle_mode() {
  local mode="${1:-all}"

  case "${mode}" in
    all)
      printf 'all\n'
      ;;
    images|image)
      printf 'images\n'
      ;;
    assets|asset|files|file)
      printf 'assets\n'
      ;;
    *)
      echo "Unsupported bundle mode: ${mode}" >&2
      echo "Expected one of: all, images, assets" >&2
      exit 1
      ;;
  esac
}
