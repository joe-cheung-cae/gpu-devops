#!/usr/bin/env bash

if [[ -n "${PROGRESS_COMMON_LOADED:-}" ]]; then
  return 0
fi
PROGRESS_COMMON_LOADED=1

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck disable=SC1091
source "${ROOT_DIR}/scripts/common/progress.sh"
