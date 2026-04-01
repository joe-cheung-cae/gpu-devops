#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env"
TEST_ENV_FILE="$(mktemp)"
trap 'rm -f "${TEST_ENV_FILE}"' EXIT

if [[ -f "${ENV_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
fi

BUILDER_IMAGE_FAMILY="${BUILDER_IMAGE_FAMILY:-tf-particles/devops/cuda-builder:cuda11.7-cmake3.26}"
TEST_PLATFORMS="${BUILDER_TEST_PLATFORMS:-${BUILDER_PLATFORMS:-centos7,rocky8,ubuntu2204}}"

IFS=',' read -r -a PLATFORMS <<< "${TEST_PLATFORMS}"

cat > "${TEST_ENV_FILE}" <<EOF
BUILDER_IMAGE_FAMILY=${BUILDER_IMAGE_FAMILY}
BUILDER_DEFAULT_PLATFORM=centos7
BUILDER_PLATFORMS=${TEST_PLATFORMS}
BUILDER_IMAGE=${BUILDER_IMAGE_FAMILY}-centos7
HOST_PROJECT_DIR=${ROOT_DIR}
CUDA_CXX_DEPS_ROOT=./artifacts/deps
EOF

for platform in "${PLATFORMS[@]}"; do
  image="${BUILDER_IMAGE_FAMILY}-${platform}"
  echo "Verifying muparserx in ${image}"
  "${ROOT_DIR}/scripts/prepare-builder-deps.sh" --env-file "${TEST_ENV_FILE}" --platform "${platform}" --deps muparserx >/dev/null
  docker run --rm -v "${ROOT_DIR}:/workspace" -w /workspace "${image}" sh -lc '
    set -e
    test -d "./artifacts/deps/'"${platform}"'/muparserx/.git"
    (
      cd "./artifacts/deps/'"${platform}"'/muparserx"
      git rev-parse --abbrev-ref HEAD
    ) | grep -Fx "master"
    test -f "./artifacts/deps/'"${platform}"'/muparserx/build/libmuparserx.so"
    ldd "./artifacts/deps/'"${platform}"'/muparserx/build/libmuparserx.so"
    find "./artifacts/deps/'"${platform}"'/muparserx-install/lib" -maxdepth 1 -name "libmuparserx.so*" | grep -q .
  '
done

echo "muparserx runtime tests passed"
