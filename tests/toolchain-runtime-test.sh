#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

run_in_image() {
  local image="$1"
  shift
  docker run --rm "${image}" bash -lc "$*"
}

assert_toolchain_basics() {
  local image="$1"
  run_in_image "${image}" '
    autoconf --version >/dev/null
    automake --version >/dev/null
    libtool --version >/dev/null || libtoolize --version >/dev/null
    pkg-config --version >/dev/null
    bison --version >/dev/null
    flex --version >/dev/null
    cmake --version >/dev/null
    ninja --version >/dev/null
    nvcc --version >/dev/null
  ' || fail "toolchain baseline missing in ${image}"
}

assert_autotools_configure() {
  local image="$1"
  run_in_image "${image}" '
    workdir="$(mktemp -d)"
    cd "${workdir}"
    cat > configure.ac <<'"'"'EOF'"'"'
AC_INIT([toolchain-smoke], [0.1])
AM_INIT_AUTOMAKE([foreign])
AC_PROG_CC
AC_CONFIG_FILES([Makefile])
AC_OUTPUT
EOF
    cat > Makefile.am <<'"'"'EOF'"'"'
bin_PROGRAMS =
EOF
    autoreconf -ivf
    ./configure
  ' || fail "autotools configure smoke test failed in ${image}"
}

assert_cmake_configure() {
  local image="$1"
  run_in_image "${image}" '
    workdir="$(mktemp -d)"
    cd "${workdir}"
    cat > CMakeLists.txt <<'"'"'EOF'"'"'
cmake_minimum_required(VERSION 3.26)
project(toolchain-smoke LANGUAGES C CXX)
find_package(ZLIB REQUIRED)
add_executable(toolchain-smoke main.cpp)
target_link_libraries(toolchain-smoke PRIVATE ZLIB::ZLIB)
EOF
    cat > main.cpp <<'"'"'EOF'"'"'
#include <zlib.h>
int main() { return zlibVersion() == nullptr; }
EOF
    cmake -G Ninja -S . -B build
  ' || fail "cmake configure smoke test failed in ${image}"
}

assert_cuda_cmake_configure() {
  local image="$1"
  run_in_image "${image}" '
    workdir="$(mktemp -d)"
    cd "${workdir}"
    cat > CMakeLists.txt <<'"'"'EOF'"'"'
cmake_minimum_required(VERSION 3.26)
project(cuda-smoke LANGUAGES CUDA CXX)
add_executable(cuda-smoke main.cu)
set_target_properties(cuda-smoke PROPERTIES CUDA_STANDARD 14)
EOF
    cat > main.cu <<'"'"'EOF'"'"'
__global__ void noop() {}
int main() { noop<<<1, 1>>>(); return 0; }
EOF
    cmake -G Ninja -S . -B build
  ' || fail "cuda cmake configure smoke test failed in ${image}"
}

BUILDER_CUDA_VERSION="12.9.1"
BUILDER_PLATFORM_CUDA_VERSIONS="centos7=12.4.0,rocky8=12.9.1,rocky9=12.9.1,ubuntu2204=12.9.1,ubuntu2404=12.9.1"
BUILDER_IMAGE_FAMILY="tf-particles/devops/cuda-builder"
BUILDER_PLATFORMS="centos7,rocky8,rocky9,ubuntu2204,ubuntu2404"

if [[ -f "${ENV_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
fi

IFS=',' read -r -a platforms <<< "${BUILDER_PLATFORMS}"

for platform in "${platforms[@]}"; do
  image_version="${BUILDER_CUDA_VERSION}"
  if [[ -n "${BUILDER_PLATFORM_CUDA_VERSIONS}" ]]; then
    IFS=',' read -r -a version_entries <<< "${BUILDER_PLATFORM_CUDA_VERSIONS}"
    for version_entry in "${version_entries[@]}"; do
      if [[ "${version_entry}" == "${platform}="* ]]; then
        image_version="${version_entry#*=}"
        break
      fi
    done
  fi
  image="${BUILDER_IMAGE_FAMILY}:${platform}-${image_version}"
  assert_toolchain_basics "${image}"
  assert_autotools_configure "${image}"
  assert_cmake_configure "${image}"
  assert_cuda_cmake_configure "${image}"
done

echo "toolchain runtime smoke tests passed"
