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
  echo "Verifying HDF5 in ${image}"
  docker run --rm "${image}" sh -lc '
    set -e
    test -f "${HOME}/deps/hdf5-install/lib/libhdf5.so"
    test -x "${HOME}/deps/hdf5-install/bin/h5cc"
    ldd_output="$(ldd "${HOME}/deps/hdf5-install/lib/libhdf5.so")"
    printf "%s\n" "${ldd_output}"
    printf "%s\n" "${ldd_output}" | grep -E "libz(\.so)?"
    "${HOME}/deps/hdf5-install/bin/h5cc" -showconfig >/dev/null
  '
done

echo "hdf5 runtime tests passed"
