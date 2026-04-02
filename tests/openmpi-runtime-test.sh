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
  echo "Verifying base image contract in ${image}"
  docker run --rm "${image}" sh -lc '
    set -e
    test -f /usr/include/uuid/uuid.h
    command -v ccache >/dev/null
    ! command -v mpicc >/dev/null
    ! command -v mpicxx >/dev/null
    ! command -v mpirun >/dev/null
    test ! -e /opt/openmpi/lib/libmpi.so
    test ! -e /usr/local/include/eigen3/Eigen/Core
  '
done

echo "base image runtime tests passed"
