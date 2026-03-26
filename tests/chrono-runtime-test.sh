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
  echo "Verifying Chrono in ${image}"
  docker run --rm "${image}" sh -lc '
    set -e
    test -d "${HOME}/deps/chrono/.git"
    (
      cd "${HOME}/deps/chrono"
      git rev-parse --short=9 HEAD
    ) | grep -Fx "3eb56218b"
    test -f "${HOME}/deps/chrono-install/lib/libChronoEngine.so"
    ldd "${HOME}/deps/chrono-install/lib/libChronoEngine.so"
    chrono_config="$(find "${HOME}/deps/chrono-install" \( -name ChronoConfig.cmake -o -name chrono-config.cmake \) -print -quit)"
    test -n "${chrono_config}"
    workdir="$(mktemp -d)"
    cat > "${workdir}/CMakeLists.txt" <<'"'"'EOF'"'"'
cmake_minimum_required(VERSION 3.16)
project(chrono_smoke LANGUAGES CXX)
find_package(Chrono CONFIG REQUIRED)
add_executable(chrono_smoke main.cpp)
target_compile_features(chrono_smoke PRIVATE cxx_std_14)
if(TARGET Chrono::ChronoEngine)
  target_link_libraries(chrono_smoke PRIVATE Chrono::ChronoEngine)
elseif(TARGET ChronoEngine)
  target_link_libraries(chrono_smoke PRIVATE ChronoEngine)
elseif(DEFINED CHRONO_LIBRARIES AND DEFINED CHRONO_INCLUDE_DIRS)
  target_include_directories(chrono_smoke PRIVATE ${CHRONO_INCLUDE_DIRS})
  target_link_libraries(chrono_smoke PRIVATE ${CHRONO_LIBRARIES})
  target_compile_options(chrono_smoke PRIVATE ${CHRONO_CXX_FLAGS})
else()
  message(FATAL_ERROR "ChronoEngine target not found")
endif()
EOF
    cat > "${workdir}/main.cpp" <<'"'"'EOF'"'"'
#include "chrono/physics/ChSystemNSC.h"

int main() {
  chrono::ChSystemNSC system;
  return system.GetNumBodies() != 0;
}
EOF
    cmake -S "${workdir}" -B "${workdir}/build" -DChrono_DIR="$(dirname "${chrono_config}")"
    cmake --build "${workdir}/build" --parallel 1
    rm -rf "${workdir}"
  '
done

echo "chrono runtime tests passed"
