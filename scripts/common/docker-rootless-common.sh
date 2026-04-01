#!/usr/bin/env bash

docker_is_rootless() {
  if ! command -v docker >/dev/null 2>&1; then
    return 1
  fi

  docker info 2>/dev/null | grep -qi 'rootless'
}

require_rootless_docker() {
  local host_os
  host_os="$(uname -s)"
  if [[ "${host_os}" != "Linux" ]]; then
    return 0
  fi

  if docker_is_rootless; then
    return 0
  fi

  if [[ "${CUDA_CXX_ALLOW_ROOTFUL_DOCKER:-0}" == "1" ]]; then
    echo "Proceeding with rootful Docker because CUDA_CXX_ALLOW_ROOTFUL_DOCKER=1" >&2
    return 0
  fi

  echo "Rootless Docker is required for project-side Docker workflows on Linux." >&2
  echo "Set CUDA_CXX_ALLOW_ROOTFUL_DOCKER=1 to bypass this check for a legacy environment." >&2
  return 1
}
