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
  echo "Verifying h5engine packages in ${image}"
  docker run --rm "${image}" sh -lc '
    set -e

    check_package() {
      local package_name="$1"
      local package_dir="${HOME}/deps/${package_name}"
      local lib_path="${package_dir}/build/h5Engine/libh5Engine.so"
      local test_path="${package_dir}/build/testHdf5"
      local ldd_output
      local test_output

      test -f "${lib_path}"
      test -x "${test_path}"

      ldd_output="$(ldd "${lib_path}")"
      printf "%s\n" "${ldd_output}"
      printf "%s\n" "${ldd_output}" | grep -F "${package_dir}/third/hdf5/lib/linux/libhdf5.so"

      test_output="$("${test_path}")"
      printf "%s\n" "${test_output}"
      printf "%s\n" "${test_output}" | grep -F "groups"
      printf "%s\n" "${test_output}" | grep -F "n"
    }

    check_package "h5engine-sph"
    check_package "h5engine-dem"
  '
done

echo "h5engine runtime tests passed"
