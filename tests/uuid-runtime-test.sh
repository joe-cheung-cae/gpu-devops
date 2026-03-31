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
  echo "Verifying uuid headers in ${image}"
  docker run --rm "${image}" sh -lc '
    set -e
    command -v ccache >/dev/null
    workdir="$(mktemp -d)"
    cat > "${workdir}/CMakeLists.txt" <<'"'"'EOF'"'"'
cmake_minimum_required(VERSION 3.16)
project(uuid_smoke LANGUAGES CXX)
add_executable(uuid_smoke main.cpp)
target_compile_features(uuid_smoke PRIVATE cxx_std_11)
EOF
    cat > "${workdir}/main.cpp" <<'"'"'EOF'"'"'
#include <uuid/uuid.h>

int main() {
  uuid_t value{};
  return static_cast<int>(value[0]);
}
EOF
    cmake -S "${workdir}" -B "${workdir}/build"
    cmake --build "${workdir}/build" --parallel 1
    rm -rf "${workdir}"
  '
done

echo "uuid runtime tests passed"
