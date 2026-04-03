#!/usr/bin/env bash

if [[ -n "${SCRIPT_COMMON_ENV_LOADED:-}" ]]; then
  return 0
fi
SCRIPT_COMMON_ENV_LOADED=1

load_image_bundle_env() {
  local root_dir="$1"
  local env_file="$2"

  if [[ ! -f "${env_file}" ]]; then
    echo "Environment file not found: ${env_file}" >&2
    exit 1
  fi

  # shellcheck disable=SC1090
  source "${env_file}"

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
