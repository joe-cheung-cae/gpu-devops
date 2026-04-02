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
CUDA_CXX_THIRD_PARTY_ROOT=./third_party
EOF

for platform in "${PLATFORMS[@]}"; do
  image="${BUILDER_IMAGE_FAMILY}-${platform}"
  echo "Verifying HDF5 in ${image}"
  "${ROOT_DIR}/scripts/prepare-builder-deps.sh" --env-file "${TEST_ENV_FILE}" --platform "${platform}" --deps hdf5 >/dev/null
  docker run --rm -v "${ROOT_DIR}:/workspace" -w /workspace "${image}" sh -lc '
    set -e
    test -f "./third_party/'"${platform}"'/hdf5-install/lib/libhdf5.so"
    test -x "./third_party/'"${platform}"'/hdf5-install/bin/h5cc"
    ldd_output="$(ldd "./third_party/'"${platform}"'/hdf5-install/lib/libhdf5.so")"
    printf "%s\n" "${ldd_output}"
    printf "%s\n" "${ldd_output}" | grep -E "libz(\.so)?"
    "./third_party/'"${platform}"'/hdf5-install/bin/h5cc" -showconfig >/dev/null
  '
done

echo "hdf5 runtime tests passed"
