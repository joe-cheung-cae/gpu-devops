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

  if [[ -z "${IMAGE_ARCHIVE_PATH:-}" ]]; then
    IMAGE_ARCHIVE_PATH="${root_dir}/artifacts/offline-images.tar.gz"
  fi
}

require_export_image_bundle_env() {
  : "${BUILDER_IMAGE:?Set BUILDER_IMAGE in .env}"

  if [[ -z "${RUNNER_DOCKER_IMAGE:-}" ]]; then
    RUNNER_DOCKER_IMAGE="${BUILDER_IMAGE}"
  fi
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

collect_bundle_images() {
  local image
  declare -A seen=()

  for image in "${BUILDER_IMAGE}" "${RUNNER_DOCKER_IMAGE}" "${RUNNER_SERVICE_IMAGE}"; do
    [[ -n "${image}" ]] || continue
    if [[ -z "${seen["${image}"]+x}" ]]; then
      printf '%s\n' "${image}"
      seen["${image}"]=1
    fi
  done
}
