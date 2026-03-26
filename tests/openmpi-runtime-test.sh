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
  echo "Verifying toolchain in ${image}"
  docker run --rm "${image}" sh -lc '
    set -e
    command -v mpicc >/dev/null
    command -v mpicxx >/dev/null
    command -v mpirun >/dev/null
    mpicc --showme:version | grep -F "Open MPI 4.1.6"
    mpicxx --showme:command | grep -F "g++"
    test -f /opt/openmpi/lib/libmpi.a
    test ! -e /opt/openmpi/lib/libmpi.so
    test -f /usr/local/include/eigen3/Eigen/Core
    workdir="$(mktemp -d)"
    cat > "${workdir}/CMakeLists.txt" <<'"'"'EOF'"'"'
cmake_minimum_required(VERSION 3.16)
project(eigen_smoke LANGUAGES CXX)
find_package(Eigen3 3.4 REQUIRED NO_MODULE)
add_executable(eigen_smoke main.cpp)
target_link_libraries(eigen_smoke PRIVATE Eigen3::Eigen)
target_compile_features(eigen_smoke PRIVATE cxx_std_11)
EOF
    cat > "${workdir}/main.cpp" <<'"'"'EOF'"'"'
#include <Eigen/Core>
int main() {
  Eigen::Matrix3f m = Eigen::Matrix3f::Identity();
  return static_cast<int>(m(0, 0) - 1.0f);
}
EOF
    cmake -S "${workdir}" -B "${workdir}/build"
    cmake --build "${workdir}/build" --parallel 1
    rm -rf "${workdir}"
  '
done

echo "toolchain runtime tests passed"
