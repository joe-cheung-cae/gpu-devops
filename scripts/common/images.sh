#!/usr/bin/env bash

if [[ -n "${SCRIPT_COMMON_IMAGES_LOADED:-}" ]]; then
  return 0
fi
SCRIPT_COMMON_IMAGES_LOADED=1

builder_platform_supported() {
  local platform="$1"
  local supported_platform

  IFS=',' read -r -a supported_platforms <<< "${BUILDER_PLATFORMS}"
  for supported_platform in "${supported_platforms[@]}"; do
    if [[ "${supported_platform}" == "${platform}" ]]; then
      return 0
    fi
  done

  return 1
}

builder_image_for_platform() {
  local platform="$1"

  if ! builder_platform_supported "${platform}"; then
    echo "Unsupported platform: ${platform}" >&2
    exit 1
  fi

  if [[ "${platform}" == "${BUILDER_DEFAULT_PLATFORM}" ]] && [[ -n "${BUILDER_IMAGE:-}" ]]; then
    printf '%s\n' "${BUILDER_IMAGE}"
    return 0
  fi

  if [[ -z "${BUILDER_IMAGE_FAMILY:-}" ]]; then
    printf '%s-%s\n' "$(builder_default_image_family "${BUILDER_CUDA_VERSION:-11.7.1}")" "${platform}"
    return 0
  fi

  printf '%s-%s\n' "${BUILDER_IMAGE_FAMILY}" "${platform}"
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

  IFS=',' read -r -a platforms <<< "${BUILDER_PLATFORMS}"
  for platform in "${platforms[@]}"; do
    printf '%s-%s\n' "$(builder_default_image_family "${BUILDER_CUDA_VERSION:-11.7.1}")" "${platform}"
  done
  return 0
}

builder_export_image_for_platform() {
  local platform="$1"
  local image

  if [[ -n "${BUILDER_IMAGE_EXPORTS:-}" ]]; then
    while IFS= read -r image; do
      [[ -n "${image}" ]] || continue
      if [[ "${image}" == *"-${platform}" ]]; then
        printf '%s\n' "${image}"
        return 0
      fi
    done < <(builder_export_images)

    echo "No exported builder image configured for platform: ${platform}" >&2
    exit 1
  fi

  builder_image_for_platform "${platform}"
}

collect_build_images() {
  local image
  declare -A seen=()

  while IFS= read -r image; do
    [[ -n "${image}" ]] || continue
    if [[ -z "${seen["${image}"]+x}" ]]; then
      printf '%s\n' "${image}"
      seen["${image}"]=1
    fi
  done < <(builder_export_images)
}

collect_build_images_for_platform() {
  local platform="$1"
  builder_export_image_for_platform "${platform}"
}

ensure_bundle_images_available() {
  local image

  for image in "$@"; do
    if ! docker image inspect "${image}" >/dev/null 2>&1; then
      docker pull "${image}"
    fi
  done
}
