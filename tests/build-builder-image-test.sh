#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_contains() {
  local file="$1"
  local expected="$2"
  if ! grep -Fq -- "${expected}" "${file}"; then
    echo "Expected to find: ${expected}" >&2
    echo "In file: ${file}" >&2
    cat "${file}" >&2 || true
    fail "missing expected content"
  fi
}

run_with_mock_docker() {
  local env_file="$1"
  local log_file="$2"
  shift 2

  local mock_bin="${TMP_DIR}/bin"
  mkdir -p "${mock_bin}"

  cat > "${mock_bin}/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${TEST_LOG_FILE:?}"
exit 0
EOF
  chmod +x "${mock_bin}/docker"

  TEST_LOG_FILE="${log_file}" PATH="${mock_bin}:${PATH}" \
    "${ROOT_DIR}/scripts/build-builder-image.sh" --env-file "${env_file}" "$@"
}

ENV_FILE="${TMP_DIR}/.env"
cat > "${ENV_FILE}" <<'EOF'
BUILDER_IMAGE_FAMILY=registry.local/devops/cuda-builder:cuda11.7-cmake3.26
BUILDER_DEFAULT_PLATFORM=centos7
BUILDER_PLATFORMS=centos7,rocky8,ubuntu2204
BUILDER_IMAGE=registry.local/devops/cuda-builder:cuda11.7-cmake3.26-centos7
EOF

default_log="${TMP_DIR}/default.log"
run_with_mock_docker "${ENV_FILE}" "${default_log}"
assert_contains "${default_log}" "-t registry.local/devops/cuda-builder:cuda11.7-cmake3.26-centos7"
assert_contains "${default_log}" "-f ${ROOT_DIR}/docker/cuda-builder/centos7.Dockerfile"

ubuntu_log="${TMP_DIR}/ubuntu.log"
run_with_mock_docker "${ENV_FILE}" "${ubuntu_log}" --platform ubuntu2204
assert_contains "${ubuntu_log}" "-t registry.local/devops/cuda-builder:cuda11.7-cmake3.26-ubuntu2204"
assert_contains "${ubuntu_log}" "-f ${ROOT_DIR}/docker/cuda-builder/ubuntu2204.Dockerfile"

all_log="${TMP_DIR}/all.log"
run_with_mock_docker "${ENV_FILE}" "${all_log}" --all-platforms
assert_contains "${all_log}" "-t registry.local/devops/cuda-builder:cuda11.7-cmake3.26-centos7"
assert_contains "${all_log}" "-f ${ROOT_DIR}/docker/cuda-builder/centos7.Dockerfile"
assert_contains "${all_log}" "-t registry.local/devops/cuda-builder:cuda11.7-cmake3.26-rocky8"
assert_contains "${all_log}" "-f ${ROOT_DIR}/docker/cuda-builder/rocky8.Dockerfile"
assert_contains "${all_log}" "-t registry.local/devops/cuda-builder:cuda11.7-cmake3.26-ubuntu2204"
assert_contains "${all_log}" "-f ${ROOT_DIR}/docker/cuda-builder/ubuntu2204.Dockerfile"

assert_contains "${ROOT_DIR}/docker/cuda-builder/centos7.Dockerfile" 'ARG EIGEN3_VERSION=3.4.0'
assert_contains "${ROOT_DIR}/docker/cuda-builder/rocky8.Dockerfile" 'ARG EIGEN3_VERSION=3.4.0'
assert_contains "${ROOT_DIR}/docker/cuda-builder/ubuntu2204.Dockerfile" 'ARG EIGEN3_VERSION=3.4.0'
assert_contains "${ROOT_DIR}/docker/cuda-builder/centos7.Dockerfile" 'ARG CHRONO_GIT_URL=https://github.com/projectchrono/chrono.git'
assert_contains "${ROOT_DIR}/docker/cuda-builder/centos7.Dockerfile" 'ARG CHRONO_GIT_REF=3eb56218b'
assert_contains "${ROOT_DIR}/docker/cuda-builder/centos7.Dockerfile" 'ARG CHRONO_BUILD_PARALLEL=6'
assert_contains "${ROOT_DIR}/docker/cuda-builder/centos7.Dockerfile" 'zlib-devel'
assert_contains "${ROOT_DIR}/docker/cuda-builder/rocky8.Dockerfile" 'ARG CHRONO_GIT_URL=https://github.com/projectchrono/chrono.git'
assert_contains "${ROOT_DIR}/docker/cuda-builder/rocky8.Dockerfile" 'ARG CHRONO_GIT_REF=3eb56218b'
assert_contains "${ROOT_DIR}/docker/cuda-builder/rocky8.Dockerfile" 'ARG CHRONO_BUILD_PARALLEL=6'
assert_contains "${ROOT_DIR}/docker/cuda-builder/rocky8.Dockerfile" 'zlib-devel'
assert_contains "${ROOT_DIR}/docker/cuda-builder/ubuntu2204.Dockerfile" 'ARG CHRONO_GIT_URL=https://github.com/projectchrono/chrono.git'
assert_contains "${ROOT_DIR}/docker/cuda-builder/ubuntu2204.Dockerfile" 'ARG CHRONO_GIT_REF=3eb56218b'
assert_contains "${ROOT_DIR}/docker/cuda-builder/ubuntu2204.Dockerfile" 'ARG CHRONO_BUILD_PARALLEL=6'
assert_contains "${ROOT_DIR}/docker/cuda-builder/ubuntu2204.Dockerfile" 'zlib1g-dev'
assert_contains "${ROOT_DIR}/docker/cuda-builder/centos7.Dockerfile" 'install-eigen3.sh'
assert_contains "${ROOT_DIR}/docker/cuda-builder/rocky8.Dockerfile" 'install-eigen3.sh'
assert_contains "${ROOT_DIR}/docker/cuda-builder/ubuntu2204.Dockerfile" 'install-eigen3.sh'
assert_contains "${ROOT_DIR}/docker/cuda-builder/centos7.Dockerfile" 'install-chrono.sh'
assert_contains "${ROOT_DIR}/docker/cuda-builder/rocky8.Dockerfile" 'install-chrono.sh'
assert_contains "${ROOT_DIR}/docker/cuda-builder/ubuntu2204.Dockerfile" 'install-chrono.sh'
assert_contains "${ROOT_DIR}/docker/cuda-builder/centos7.Dockerfile" 'CMake-hdf5-1.14.1-2.tar.gz'
assert_contains "${ROOT_DIR}/docker/cuda-builder/rocky8.Dockerfile" 'CMake-hdf5-1.14.1-2.tar.gz'
assert_contains "${ROOT_DIR}/docker/cuda-builder/ubuntu2204.Dockerfile" 'CMake-hdf5-1.14.1-2.tar.gz'
assert_contains "${ROOT_DIR}/docker/cuda-builder/centos7.Dockerfile" 'install-hdf5.sh'
assert_contains "${ROOT_DIR}/docker/cuda-builder/rocky8.Dockerfile" 'install-hdf5.sh'
assert_contains "${ROOT_DIR}/docker/cuda-builder/ubuntu2204.Dockerfile" 'install-hdf5.sh'
assert_contains "${ROOT_DIR}/docker/cuda-builder/centos7.Dockerfile" 'h5engine-sph.tar.gz'
assert_contains "${ROOT_DIR}/docker/cuda-builder/centos7.Dockerfile" 'h5engine-dem.tar.gz'
assert_contains "${ROOT_DIR}/docker/cuda-builder/rocky8.Dockerfile" 'h5engine-sph.tar.gz'
assert_contains "${ROOT_DIR}/docker/cuda-builder/rocky8.Dockerfile" 'h5engine-dem.tar.gz'
assert_contains "${ROOT_DIR}/docker/cuda-builder/ubuntu2204.Dockerfile" 'h5engine-sph.tar.gz'
assert_contains "${ROOT_DIR}/docker/cuda-builder/ubuntu2204.Dockerfile" 'h5engine-dem.tar.gz'
assert_contains "${ROOT_DIR}/docker/cuda-builder/centos7.Dockerfile" 'install-h5engine.sh'
assert_contains "${ROOT_DIR}/docker/cuda-builder/rocky8.Dockerfile" 'install-h5engine.sh'
assert_contains "${ROOT_DIR}/docker/cuda-builder/ubuntu2204.Dockerfile" 'install-h5engine.sh'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-eigen3.sh" 'EIGEN3_VERSION:=3.4.0'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-eigen3.sh" 'EIGEN3_PREFIX:=/usr/local'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-eigen3.sh" 'gitlab.com/libeigen/eigen/-/archive/${EIGEN3_VERSION}/${ARCHIVE}'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-chrono.sh" 'CHRONO_GIT_URL:=https://github.com/projectchrono/chrono.git'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-chrono.sh" 'CHRONO_GIT_REF:=3eb56218b'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-chrono.sh" 'CHRONO_SOURCE_DIR:=${HOME}/deps/chrono'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-chrono.sh" 'CHRONO_INSTALL_PREFIX:=${HOME}/deps/chrono-install'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-chrono.sh" 'CHRONO_BUILD_PARALLEL:=6'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-chrono.sh" "target_link_libraries(ChronoEngine -static-libgcc -static-libstdc++)"
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-hdf5.sh" 'HDF5_ARCHIVE:=docker/cuda-builder/deps/CMake-hdf5-1.14.1-2.tar.gz'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-hdf5.sh" 'HDF5_INSTALL_PREFIX:=/root/deps/hdf5-install'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-hdf5.sh" 'HDF5_BUILD_PARALLEL:=${CHRONO_BUILD_PARALLEL:-6}'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-hdf5.sh" './configure --prefix=/root/deps/hdf5-install'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-hdf5.sh" 'make -j"${HDF5_BUILD_PARALLEL}"'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-hdf5.sh" 'ldd "${HDF5_INSTALL_PREFIX}/lib/libhdf5.so"'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-h5engine.sh" 'H5ENGINE_BUILD_PARALLEL:=${CHRONO_BUILD_PARALLEL:-6}'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-h5engine.sh" 'H5ENGINE_SPH_ARCHIVE:=docker/cuda-builder/deps/h5engine-sph.tar.gz'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-h5engine.sh" 'H5ENGINE_DEM_ARCHIVE:=docker/cuda-builder/deps/h5engine-dem.tar.gz'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-h5engine.sh" 'test -f "${HOME}/deps/hdf5-install/lib/libhdf5.so"'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-h5engine.sh" 'rm -rf "${package_dir}/third/hdf5/include/linux"/*'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-h5engine.sh" 'cp -a "${HDF5_INSTALL_PREFIX}/include/." "${package_dir}/third/hdf5/include/linux/"'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-h5engine.sh" 'rm -rf "${package_dir}/third/hdf5/lib/linux"/*'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-h5engine.sh" 'cp -a "${HDF5_INSTALL_PREFIX}/lib/libhdf5.so"* "${package_dir}/third/hdf5/lib/linux/"'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-h5engine.sh" 'cmake .. -DCMAKE_BUILD_TYPE=Release'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-h5engine.sh" 'make -j"${H5ENGINE_BUILD_PARALLEL}"'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-h5engine.sh" 'ldd ./build/h5Engine/libh5Engine.so'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-h5engine.sh" './build/testHdf5'

assert_contains "${ROOT_DIR}/docker/cuda-builder/centos7.Dockerfile" 'ARG http_proxy'
assert_contains "${ROOT_DIR}/docker/cuda-builder/centos7.Dockerfile" 'ARG HTTP_PROXY'
assert_contains "${ROOT_DIR}/docker/cuda-builder/centos7.Dockerfile" 'YUM_PROXY="${http_proxy:-${HTTP_PROXY}}"'
assert_contains "${ROOT_DIR}/docker/cuda-builder/centos7.Dockerfile" 'echo "proxy=${YUM_PROXY}" >> /etc/yum.conf'
assert_contains "${ROOT_DIR}/docker/cuda-builder/centos7.Dockerfile" 'devtoolset-11-gcc'
assert_contains "${ROOT_DIR}/docker/cuda-builder/centos7.Dockerfile" 'ENV PATH="/opt/rh/devtoolset-11/root/usr/bin:${PATH}"'
assert_contains "${ROOT_DIR}/docker/cuda-builder/rocky8.Dockerfile" 'gcc-toolset-11-gcc-c++'
assert_contains "${ROOT_DIR}/docker/cuda-builder/rocky8.Dockerfile" 'ENV PATH="/opt/rh/gcc-toolset-11/root/usr/bin:${PATH}"'

echo "build builder image tests passed"
