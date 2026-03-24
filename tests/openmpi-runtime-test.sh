#!/usr/bin/env bash
set -euo pipefail

IMAGES=(
  "registry.example.com/devops/cuda-builder:cuda11.7-cmake3.26-centos7"
  "registry.example.com/devops/cuda-builder:cuda11.7-cmake3.26-rocky8"
  "registry.example.com/devops/cuda-builder:cuda11.7-cmake3.26-ubuntu2204"
)

for image in "${IMAGES[@]}"; do
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
