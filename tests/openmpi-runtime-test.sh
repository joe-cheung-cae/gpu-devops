#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env"

if [[ -f "${ENV_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
fi

BUILDER_IMAGE_FAMILY="${BUILDER_IMAGE_FAMILY:-tf-particles/devops/cuda-builder:cuda11.7-cmake3.26}"
BUILDER_PLATFORMS="${BUILDER_PLATFORMS:-centos7,rocky8,ubuntu2204}"

IFS=',' read -r -a PLATFORMS <<< "${BUILDER_PLATFORMS}"

for platform in "${PLATFORMS[@]}"; do
  image="${BUILDER_IMAGE_FAMILY}-${platform}"
  echo "Verifying OpenMPI in ${image}"
  docker run --rm "${image}" sh -lc '
    set -e
    command -v mpicc >/dev/null
    command -v mpicxx >/dev/null
    command -v mpirun >/dev/null
    mpicc --showme:version | grep -F "Open MPI 4.1.6"
    mpicxx --showme:command | grep -F "g++"
    test -f /opt/openmpi/lib/libmpi.a
    test ! -e /opt/openmpi/lib/libmpi.so
  '
done

echo "openmpi runtime tests passed"
