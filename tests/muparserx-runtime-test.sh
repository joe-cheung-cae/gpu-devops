#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env"

if [[ -f "${ENV_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
fi

BUILDER_IMAGE_FAMILY="${BUILDER_IMAGE_FAMILY:-tf-particles/devops/cuda-builder:cuda11.7-cmake3.26}"
TEST_PLATFORMS="${BUILDER_TEST_PLATFORMS:-${BUILDER_PLATFORMS:-centos7,rocky8,ubuntu2204}}"

IFS=',' read -r -a PLATFORMS <<< "${TEST_PLATFORMS}"

for platform in "${PLATFORMS[@]}"; do
  image="${BUILDER_IMAGE_FAMILY}-${platform}"
  echo "Verifying muparserx in ${image}"
  docker run --rm "${image}" sh -lc '
    set -e
    test -d "${HOME}/deps/muparserx/.git"
    (
      cd "${HOME}/deps/muparserx"
      git rev-parse --abbrev-ref HEAD
    ) | grep -Fx "master"
    test -f "${HOME}/deps/muparserx/build/libmuparserx.so"
    ldd "${HOME}/deps/muparserx/build/libmuparserx.so"
    find "${HOME}/deps/muparserx-install/lib" -maxdepth 1 -name "libmuparserx.so*" | grep -q .
  '
done

echo "muparserx runtime tests passed"
