#!/usr/bin/env bash

if [[ -n "${IMAGE_BUNDLE_COMMON_LOADED:-}" ]]; then
  return 0
fi
IMAGE_BUNDLE_COMMON_LOADED=1

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck disable=SC1091
source "${ROOT_DIR}/scripts/common/env.sh"
# shellcheck disable=SC1091
source "${ROOT_DIR}/scripts/common/images.sh"
# shellcheck disable=SC1091
source "${ROOT_DIR}/scripts/common/archive.sh"
# shellcheck disable=SC1091
source "${ROOT_DIR}/scripts/common/project-bundle.sh"
