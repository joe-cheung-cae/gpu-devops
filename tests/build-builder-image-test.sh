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

assert_not_contains() {
  local file="$1"
  local unexpected="$2"
  if grep -Fq -- "${unexpected}" "${file}"; then
    echo "Did not expect to find: ${unexpected}" >&2
    echo "In file: ${file}" >&2
    cat "${file}" >&2 || true
    fail "unexpected content present"
  fi
}

assert_service_block_not_contains() {
  local start_marker="$1"
  local end_marker="$2"
  local unexpected="$3"
  local block

  block="$(awk -v start="${start_marker}" -v end="${end_marker}" '
    $0 == start {in_block=1; next}
    in_block && $0 == end {exit}
    in_block {print}
  ' "${ROOT_DIR}/docker-compose.yml")"

  if grep -Fq -- "${unexpected}" <<< "${block}"; then
    echo "Did not expect to find: ${unexpected}" >&2
    echo "In service block starting at: ${start_marker}" >&2
    printf '%s\n' "${block}" >&2
    fail "unexpected content present"
  fi
}

run_with_mock_docker() {
  local env_file="$1"
  local log_file="$2"
  local stdout_file="$3"
  shift 3

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
    "${ROOT_DIR}/scripts/build-builder-image.sh" --env-file "${env_file}" "$@" > "${stdout_file}"
}

ENV_FILE="${TMP_DIR}/.env"
cat > "${ENV_FILE}" <<'EOF'
BUILDER_IMAGE_FAMILY=registry.local/devops/cuda-builder:cuda11.7-cmake3.26
BUILDER_DEFAULT_PLATFORM=centos7
BUILDER_PLATFORMS=centos7,rocky8,ubuntu2204
BUILDER_IMAGE=registry.local/devops/cuda-builder:cuda11.7-cmake3.26-centos7
EOF

default_log="${TMP_DIR}/default.log"
default_stdout="${TMP_DIR}/default.stdout"
run_with_mock_docker "${ENV_FILE}" "${default_log}" "${default_stdout}"
assert_contains "${default_log}" "-t registry.local/devops/cuda-builder:cuda11.7-cmake3.26-centos7"
assert_contains "${default_log}" "-f ${ROOT_DIR}/docker/cuda-builder/centos7.Dockerfile"
assert_contains "${default_stdout}" "[1/5] Loading environment"
assert_contains "${default_stdout}" "[5/5] Completed builder image build workflow"

ubuntu_log="${TMP_DIR}/ubuntu.log"
ubuntu_stdout="${TMP_DIR}/ubuntu.stdout"
run_with_mock_docker "${ENV_FILE}" "${ubuntu_log}" "${ubuntu_stdout}" --platform ubuntu2204
assert_contains "${ubuntu_log}" "-t registry.local/devops/cuda-builder:cuda11.7-cmake3.26-ubuntu2204"
assert_contains "${ubuntu_log}" "-f ${ROOT_DIR}/docker/cuda-builder/ubuntu2204.Dockerfile"

all_log="${TMP_DIR}/all.log"
all_stdout="${TMP_DIR}/all.stdout"
run_with_mock_docker "${ENV_FILE}" "${all_log}" "${all_stdout}" --all-platforms
assert_contains "${all_log}" "-t registry.local/devops/cuda-builder:cuda11.7-cmake3.26-centos7"
assert_contains "${all_log}" "-f ${ROOT_DIR}/docker/cuda-builder/centos7.Dockerfile"
assert_contains "${all_log}" "-t registry.local/devops/cuda-builder:cuda11.7-cmake3.26-rocky8"
assert_contains "${all_log}" "-f ${ROOT_DIR}/docker/cuda-builder/rocky8.Dockerfile"
assert_contains "${all_log}" "-t registry.local/devops/cuda-builder:cuda11.7-cmake3.26-ubuntu2204"
assert_contains "${all_log}" "-f ${ROOT_DIR}/docker/cuda-builder/ubuntu2204.Dockerfile"
assert_contains "${all_stdout}" "[4/5] Building platform image centos7"
assert_contains "${all_stdout}" "[4/5] Building platform image rocky8"
assert_contains "${all_stdout}" "[4/5] Building platform image ubuntu2204"

assert_contains "${ROOT_DIR}/docker/cuda-builder/centos7.Dockerfile" 'zlib-devel'
assert_contains "${ROOT_DIR}/docker/cuda-builder/centos7.Dockerfile" 'libuuid-devel'
assert_contains "${ROOT_DIR}/docker/cuda-builder/centos7.Dockerfile" 'ccache'
assert_contains "${ROOT_DIR}/docker/cuda-builder/centos7.Dockerfile" 'epel-release'
assert_contains "${ROOT_DIR}/docker/cuda-builder/rocky8.Dockerfile" 'zlib-devel'
assert_contains "${ROOT_DIR}/docker/cuda-builder/rocky8.Dockerfile" 'libuuid-devel'
assert_contains "${ROOT_DIR}/docker/cuda-builder/rocky8.Dockerfile" 'ccache'
assert_contains "${ROOT_DIR}/docker/cuda-builder/rocky8.Dockerfile" 'epel-release'
assert_contains "${ROOT_DIR}/docker/cuda-builder/ubuntu2204.Dockerfile" 'zlib1g-dev'
assert_contains "${ROOT_DIR}/docker/cuda-builder/ubuntu2204.Dockerfile" 'uuid-dev'
assert_contains "${ROOT_DIR}/docker/cuda-builder/ubuntu2204.Dockerfile" 'ccache'
assert_not_contains "${ROOT_DIR}/docker/cuda-builder/centos7.Dockerfile" 'ARG EIGEN3_VERSION=3.4.0'
assert_not_contains "${ROOT_DIR}/docker/cuda-builder/rocky8.Dockerfile" 'ARG EIGEN3_VERSION=3.4.0'
assert_not_contains "${ROOT_DIR}/docker/cuda-builder/ubuntu2204.Dockerfile" 'ARG EIGEN3_VERSION=3.4.0'
assert_not_contains "${ROOT_DIR}/docker/cuda-builder/centos7.Dockerfile" 'ARG OPENMPI_VERSION=4.1.6'
assert_not_contains "${ROOT_DIR}/docker/cuda-builder/rocky8.Dockerfile" 'ARG OPENMPI_VERSION=4.1.6'
assert_not_contains "${ROOT_DIR}/docker/cuda-builder/ubuntu2204.Dockerfile" 'ARG OPENMPI_VERSION=4.1.6'
assert_not_contains "${ROOT_DIR}/docker/cuda-builder/centos7.Dockerfile" 'install-eigen3.sh'
assert_not_contains "${ROOT_DIR}/docker/cuda-builder/rocky8.Dockerfile" 'install-eigen3.sh'
assert_not_contains "${ROOT_DIR}/docker/cuda-builder/ubuntu2204.Dockerfile" 'install-eigen3.sh'
assert_not_contains "${ROOT_DIR}/docker/cuda-builder/centos7.Dockerfile" 'install-openmpi.sh'
assert_not_contains "${ROOT_DIR}/docker/cuda-builder/rocky8.Dockerfile" 'install-openmpi.sh'
assert_not_contains "${ROOT_DIR}/docker/cuda-builder/ubuntu2204.Dockerfile" 'install-openmpi.sh'
assert_not_contains "${ROOT_DIR}/docker/cuda-builder/centos7.Dockerfile" 'OPENMPI_PREFIX=/opt/openmpi'
assert_not_contains "${ROOT_DIR}/docker/cuda-builder/rocky8.Dockerfile" 'OPENMPI_PREFIX=/opt/openmpi'
assert_not_contains "${ROOT_DIR}/docker/cuda-builder/ubuntu2204.Dockerfile" 'OPENMPI_PREFIX=/opt/openmpi'
assert_not_contains "${ROOT_DIR}/docker/cuda-builder/centos7.Dockerfile" 'install-chrono.sh'
assert_not_contains "${ROOT_DIR}/docker/cuda-builder/rocky8.Dockerfile" 'install-chrono.sh'
assert_not_contains "${ROOT_DIR}/docker/cuda-builder/ubuntu2204.Dockerfile" 'install-chrono.sh'
assert_not_contains "${ROOT_DIR}/docker/cuda-builder/centos7.Dockerfile" 'CMake-hdf5-1.14.1-2.tar.gz'
assert_not_contains "${ROOT_DIR}/docker/cuda-builder/rocky8.Dockerfile" 'CMake-hdf5-1.14.1-2.tar.gz'
assert_not_contains "${ROOT_DIR}/docker/cuda-builder/ubuntu2204.Dockerfile" 'CMake-hdf5-1.14.1-2.tar.gz'
assert_not_contains "${ROOT_DIR}/docker/cuda-builder/centos7.Dockerfile" 'install-hdf5.sh'
assert_not_contains "${ROOT_DIR}/docker/cuda-builder/rocky8.Dockerfile" 'install-hdf5.sh'
assert_not_contains "${ROOT_DIR}/docker/cuda-builder/ubuntu2204.Dockerfile" 'install-hdf5.sh'
assert_not_contains "${ROOT_DIR}/docker/cuda-builder/centos7.Dockerfile" 'h5engine-sph.tar.gz'
assert_not_contains "${ROOT_DIR}/docker/cuda-builder/centos7.Dockerfile" 'h5engine-dem.tar.gz'
assert_not_contains "${ROOT_DIR}/docker/cuda-builder/rocky8.Dockerfile" 'h5engine-sph.tar.gz'
assert_not_contains "${ROOT_DIR}/docker/cuda-builder/rocky8.Dockerfile" 'h5engine-dem.tar.gz'
assert_not_contains "${ROOT_DIR}/docker/cuda-builder/ubuntu2204.Dockerfile" 'h5engine-sph.tar.gz'
assert_not_contains "${ROOT_DIR}/docker/cuda-builder/ubuntu2204.Dockerfile" 'h5engine-dem.tar.gz'
assert_not_contains "${ROOT_DIR}/docker/cuda-builder/centos7.Dockerfile" 'install-h5engine.sh'
assert_not_contains "${ROOT_DIR}/docker/cuda-builder/rocky8.Dockerfile" 'install-h5engine.sh'
assert_not_contains "${ROOT_DIR}/docker/cuda-builder/ubuntu2204.Dockerfile" 'install-h5engine.sh'
assert_not_contains "${ROOT_DIR}/docker/cuda-builder/centos7.Dockerfile" 'install-muparserx.sh'
assert_not_contains "${ROOT_DIR}/docker/cuda-builder/rocky8.Dockerfile" 'install-muparserx.sh'
assert_not_contains "${ROOT_DIR}/docker/cuda-builder/ubuntu2204.Dockerfile" 'install-muparserx.sh'
assert_contains "${ROOT_DIR}/docker/cuda-builder/centos7.Dockerfile" 'cmake-3.26.0-linux-x86_64.tar.gz'
assert_contains "${ROOT_DIR}/docker/cuda-builder/rocky8.Dockerfile" 'cmake-3.26.0-linux-x86_64.tar.gz'
assert_contains "${ROOT_DIR}/docker/cuda-builder/ubuntu2204.Dockerfile" 'cmake-3.26.0-linux-x86_64.tar.gz'
assert_contains "${ROOT_DIR}/docker/cuda-builder/centos7.Dockerfile" 'tar -xzf /tmp/deps/cmake-3.26.0-linux-x86_64.tar.gz -C /usr/local --strip-components=1'
assert_contains "${ROOT_DIR}/docker/cuda-builder/rocky8.Dockerfile" 'tar -xzf /tmp/deps/cmake-3.26.0-linux-x86_64.tar.gz -C /usr/local --strip-components=1'
assert_contains "${ROOT_DIR}/docker/cuda-builder/ubuntu2204.Dockerfile" 'tar -xzf /tmp/deps/cmake-3.26.0-linux-x86_64.tar.gz -C /usr/local --strip-components=1'
assert_not_contains "${ROOT_DIR}/docker/cuda-builder/centos7.Dockerfile" 'wget -qO /tmp/cmake.sh'
assert_not_contains "${ROOT_DIR}/docker/cuda-builder/rocky8.Dockerfile" 'wget -qO /tmp/cmake.sh'
assert_not_contains "${ROOT_DIR}/docker/cuda-builder/ubuntu2204.Dockerfile" 'wget -qO /tmp/cmake.sh'
assert_not_contains "${ROOT_DIR}/docker/cuda-builder/centos7.Dockerfile" 'sh /tmp/cmake.sh --skip-license --prefix=/usr/local'
assert_not_contains "${ROOT_DIR}/docker/cuda-builder/rocky8.Dockerfile" 'sh /tmp/cmake.sh --skip-license --prefix=/usr/local'
assert_not_contains "${ROOT_DIR}/docker/cuda-builder/ubuntu2204.Dockerfile" 'sh /tmp/cmake.sh --skip-license --prefix=/usr/local'
assert_not_contains "${ROOT_DIR}/docker/cuda-builder/centos7.Dockerfile" 'ARG CMAKE_VERSION=3.26.0'
assert_not_contains "${ROOT_DIR}/docker/cuda-builder/rocky8.Dockerfile" 'ARG CMAKE_VERSION=3.26.0'
assert_not_contains "${ROOT_DIR}/docker/cuda-builder/ubuntu2204.Dockerfile" 'ARG CMAKE_VERSION=3.26.0'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-eigen3.sh" 'EIGEN3_VERSION:=3.4.0'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-eigen3.sh" 'DEPS_ROOT:=${HOME}/deps'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-eigen3.sh" 'EIGEN3_INSTALL_PREFIX:=${DEPS_ROOT}/eigen3-install'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-eigen3.sh" 'EIGEN3_ARCHIVE:=/tmp/deps/eigen-3.4.0.tar.gz'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-eigen3.sh" '.eigen3-source-version'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-eigen3.sh" 'test -f "${EIGEN3_ARCHIVE}"'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-eigen3.sh" 'gitlab.com/libeigen/eigen/-/archive/${EIGEN3_VERSION}/${ARCHIVE}'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-eigen3.sh" '--no-same-owner'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-eigen3.sh" '--no-same-permissions'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-eigen3.sh" 'cmake --install "${BUILD_DIR}"'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-openmpi.sh" 'DEPS_ROOT:=${HOME}/deps'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-openmpi.sh" 'OPENMPI_INSTALL_PREFIX:=${DEPS_ROOT}/openmpi-install'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-openmpi.sh" 'OPENMPI_ARCHIVE:=/tmp/deps/openmpi-4.1.6.tar.gz'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-openmpi.sh" '.openmpi-source-version'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-openmpi.sh" 'test -f "${OPENMPI_ARCHIVE}"'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-openmpi.sh" '--no-same-owner'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-openmpi.sh" '--no-same-permissions'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-openmpi.sh" '--enable-mpi-cxx'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-openmpi.sh" 'make install'
assert_not_contains "${ROOT_DIR}/docker/cuda-builder/install-openmpi.sh" ' -m'
assert_not_contains "${ROOT_DIR}/docker/cuda-builder/install-openmpi.sh" 'if [[ -n "${OPENMPI_PREFIX}" ]]'
assert_not_contains "${ROOT_DIR}/docker/cuda-builder/install-openmpi.sh" 'OPENMPI_INSTALL_PREFIX="${OPENMPI_PREFIX}"'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-chrono.sh" 'CHRONO_GIT_URL:=https://github.com/projectchrono/chrono.git'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-chrono.sh" 'CHRONO_GIT_REF:=3eb56218b'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-chrono.sh" 'DEPS_ROOT:=${HOME}/deps'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-chrono.sh" 'CHRONO_SOURCE_DIR:=${DEPS_ROOT}/chrono'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-chrono.sh" 'CHRONO_INSTALL_PREFIX:=${DEPS_ROOT}/chrono-install'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-chrono.sh" 'CHRONO_BUILD_PARALLEL:=6'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-chrono.sh" 'CHRONO_ARCHIVE:=/tmp/deps/chrono-source.tar.gz'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-chrono.sh" 'CHRONO_CMAKE_GENERATOR:=Ninja'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-chrono.sh" '.chrono-source-ref'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-chrono.sh" 'test -f "${CHRONO_ARCHIVE}"'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-chrono.sh" 'git fetch --depth 1 origin "${CHRONO_GIT_REF}"'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-chrono.sh" 'git fetch origin "${CHRONO_GIT_REF}"'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-chrono.sh" '-DBUILD_DEMOS=OFF'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-chrono.sh" '-DBUILD_TESTING=OFF'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-chrono.sh" '-DBUILD_BENCHMARKING=OFF'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-chrono.sh" "target_link_libraries(ChronoEngine -static-libgcc -static-libstdc++)"
assert_not_contains "${ROOT_DIR}/docker/cuda-builder/install-chrono.sh" "target_link_libraries(Chrono_core -static-libgcc -static-libstdc++)"
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-chrono.sh" 'cmake -G "${CHRONO_CMAKE_GENERATOR}" ..'
if grep -Fq -- 'git fetch --all --tags' "${ROOT_DIR}/docker/cuda-builder/install-chrono.sh"; then
  fail "install-chrono.sh should not use git fetch --all --tags"
fi
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-hdf5.sh" 'HDF5_ARCHIVE:=docker/cuda-builder/deps/CMake-hdf5-1.14.1-2.tar.gz'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-hdf5.sh" 'DEPS_ROOT:=${HOME}/deps'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-hdf5.sh" 'HDF5_INSTALL_PREFIX:=${DEPS_ROOT}/hdf5-install'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-hdf5.sh" 'HDF5_BUILD_PARALLEL:=${CHRONO_BUILD_PARALLEL:-6}'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-hdf5.sh" 'SOURCE_DIR="${EXTRACT_ROOT}/CMake-hdf5-1.14.1-2/hdf5-1.14.1-2"'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-hdf5.sh" './configure --prefix="${HDF5_INSTALL_PREFIX}"'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-hdf5.sh" 'mkdir -p "${EXTRACT_ROOT}"'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-hdf5.sh" '-C "${EXTRACT_ROOT}"'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-hdf5.sh" '--no-same-owner'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-hdf5.sh" '--no-same-permissions'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-hdf5.sh" 'make -j"${HDF5_BUILD_PARALLEL}"'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-hdf5.sh" 'ldd "${HDF5_INSTALL_PREFIX}/lib/libhdf5.so"'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-hdf5.sh" '.hdf5-source-version'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-h5engine.sh" 'H5ENGINE_BUILD_PARALLEL:=${CHRONO_BUILD_PARALLEL:-6}'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-h5engine.sh" 'H5ENGINE_SPH_ARCHIVE:=docker/cuda-builder/deps/h5engine-sph.tar.gz'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-h5engine.sh" 'H5ENGINE_DEM_ARCHIVE:=docker/cuda-builder/deps/h5engine-dem.tar.gz'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-h5engine.sh" 'DEPS_ROOT:=${HOME}/deps'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-h5engine.sh" 'test -f "${HDF5_INSTALL_PREFIX}/lib/libhdf5.so"'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-h5engine.sh" 'H5ENGINE_OUTPUT_ROOT:=${DEPS_ROOT}'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-h5engine.sh" 'rm -rf "${package_dir}/third/hdf5/include/linux"/*'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-h5engine.sh" 'cp -a "${HDF5_INSTALL_PREFIX}/include/." "${package_dir}/third/hdf5/include/linux/"'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-h5engine.sh" 'rm -rf "${package_dir}/third/hdf5/lib/linux"/*'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-h5engine.sh" 'cp -a "${HDF5_INSTALL_PREFIX}/lib/libhdf5.so"* "${package_dir}/third/hdf5/lib/linux/"'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-h5engine.sh" '--no-same-owner'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-h5engine.sh" '--no-same-permissions'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-h5engine.sh" 'cmake .. -DCMAKE_BUILD_TYPE=Release'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-h5engine.sh" 'make -j"${H5ENGINE_BUILD_PARALLEL}"'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-h5engine.sh" 'ldd ./build/h5Engine/libh5Engine.so'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-h5engine.sh" './build/testHdf5'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-h5engine.sh" 'build_package "h5engine-sph" "${H5ENGINE_SPH_ARCHIVE}"'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-h5engine.sh" 'build_package "h5engine-dem" "${H5ENGINE_DEM_ARCHIVE}"'
assert_not_contains "${ROOT_DIR}/docker/cuda-builder/install-h5engine.sh" 'build_package "h5engine-sph" "/tmp/$(basename "${H5ENGINE_SPH_ARCHIVE}")"'
assert_not_contains "${ROOT_DIR}/docker/cuda-builder/install-h5engine.sh" 'build_package "h5engine-dem" "/tmp/$(basename "${H5ENGINE_DEM_ARCHIVE}")"'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-muparserx.sh" 'MUPARSERX_GIT_URL:=https://github.com/joe-cheung-cae/muparserx.git'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-muparserx.sh" 'MUPARSERX_GIT_BRANCH:=master'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-muparserx.sh" 'DEPS_ROOT:=${HOME}/deps'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-muparserx.sh" 'MUPARSERX_SOURCE_DIR:=${DEPS_ROOT}/muparserx'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-muparserx.sh" 'MUPARSERX_INSTALL_PREFIX:=${DEPS_ROOT}/muparserx-install'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-muparserx.sh" 'MUPARSERX_BUILD_PARALLEL:=${CHRONO_BUILD_PARALLEL:-6}'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-muparserx.sh" 'git clone "${MUPARSERX_GIT_URL}" "${MUPARSERX_SOURCE_DIR}"'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-muparserx.sh" 'git checkout --force "${MUPARSERX_GIT_BRANCH}"'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-muparserx.sh" 'cmake .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="${MUPARSERX_INSTALL_PREFIX}"'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-muparserx.sh" 'make -j"${MUPARSERX_BUILD_PARALLEL}"'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-muparserx.sh" 'cmake --install .'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-muparserx.sh" 'ldd build/libmuparserx.so'
assert_contains "${ROOT_DIR}/docker/cuda-builder/install-muparserx.sh" '.muparserx-source-ref'
assert_contains "${ROOT_DIR}/scripts/prepare-builder-deps.sh" 'Usage: scripts/prepare-builder-deps.sh'
assert_contains "${ROOT_DIR}/scripts/prepare-builder-deps.sh" '--platform centos7|rocky8|ubuntu2204'
assert_contains "${ROOT_DIR}/scripts/prepare-builder-deps.sh" '--deps chrono,eigen3,openmpi,hdf5,h5engine,muparserx'
assert_contains "${ROOT_DIR}/scripts/prepare-builder-deps.sh" 'CUDA_CXX_DEPS_ROOT'
assert_contains "${ROOT_DIR}/scripts/prepare-builder-deps.sh" 'id -u'
assert_contains "${ROOT_DIR}/scripts/prepare-builder-deps.sh" 'id -g'
assert_contains "${ROOT_DIR}/scripts/prepare-builder-deps.sh" '--user "${RUN_UID}:${RUN_GID}"'
assert_contains "${ROOT_DIR}/scripts/prepare-builder-deps.sh" 'CUDA_CXX_ALLOW_ROOTFUL_DOCKER'
assert_contains "${ROOT_DIR}/scripts/prepare-builder-deps.sh" 'CONTAINER_HOME="/tmp/cuda-cxx-home"'
assert_contains "${ROOT_DIR}/scripts/prepare-builder-deps.sh" '-e "HOME=${CONTAINER_HOME}"'
assert_contains "${ROOT_DIR}/scripts/prepare-builder-deps.sh" '-e "CCACHE_DIR=${CONTAINER_HOME}/.ccache"'
assert_contains "${ROOT_DIR}/scripts/prepare-builder-deps.sh" "mkdir -p '\${CONTAINER_HOME}/.ccache'"
assert_contains "${ROOT_DIR}/scripts/prepare-builder-deps.sh" 'source "${ROOT_DIR}/scripts/common/third-party-registry.sh"'
assert_contains "${ROOT_DIR}/scripts/prepare-builder-deps.sh" 'source "${ROOT_DIR}/scripts/common/docker-rootless-common.sh"'
assert_contains "${ROOT_DIR}/scripts/prepare-third-party-cache.sh" 'Usage: scripts/prepare-third-party-cache.sh'
assert_contains "${ROOT_DIR}/scripts/prepare-third-party-cache.sh" 'source "${ROOT_DIR}/scripts/common/third-party-registry.sh"'
assert_contains "${ROOT_DIR}/scripts/prepare-third-party-cache.sh" '--deps chrono,eigen3,openmpi,hdf5,h5engine,muparserx'
assert_contains "${ROOT_DIR}/scripts/prepare-third-party-cache.sh" '--offline-only'
assert_contains "${ROOT_DIR}/scripts/install-third-party.sh" 'Usage: scripts/install-third-party.sh'
assert_contains "${ROOT_DIR}/scripts/install-third-party.sh" 'source "${ROOT_DIR}/scripts/common/third-party-registry.sh"'
assert_contains "${ROOT_DIR}/scripts/install-third-party.sh" '--host linux|windows'
assert_contains "${ROOT_DIR}/scripts/install-third-party.sh" 'vswhere'
assert_contains "${ROOT_DIR}/scripts/install-third-party.sh" 'MSMPI'
assert_contains "${ROOT_DIR}/scripts/compose.sh" 'CUDA_CXX_RUN_UID'
assert_contains "${ROOT_DIR}/scripts/compose.sh" 'CUDA_CXX_RUN_GID'
assert_contains "${ROOT_DIR}/scripts/compose.sh" 'id -u'
assert_contains "${ROOT_DIR}/scripts/compose.sh" 'id -g'
assert_contains "${ROOT_DIR}/scripts/compose.sh" 'CUDA_CXX_ALLOW_ROOTFUL_DOCKER'
assert_contains "${ROOT_DIR}/scripts/compose.sh" 'source "${ROOT_DIR}/scripts/common/docker-rootless-common.sh"'
assert_contains "${ROOT_DIR}/scripts/common/docker-rootless-common.sh" 'require_rootless_docker'
assert_contains "${ROOT_DIR}/scripts/common/docker-rootless-common.sh" 'CUDA_CXX_ALLOW_ROOTFUL_DOCKER'
assert_contains "${ROOT_DIR}/scripts/common/docker-rootless-common.sh" "docker info"
assert_contains "${ROOT_DIR}/scripts/common/third-party-registry.sh" 'third_party_validate_dep'
assert_contains "${ROOT_DIR}/scripts/common/third-party-registry.sh" 'third_party_all_deps_csv'
assert_contains "${ROOT_DIR}/scripts/common/third-party-registry.sh" 'third_party_resolve_dep_order'
assert_contains "${ROOT_DIR}/scripts/common/third-party-registry.sh" '/toolkit/docker/cuda-builder/install-eigen3.sh'
assert_contains "${ROOT_DIR}/scripts/common/third-party-registry.sh" '/toolkit/docker/cuda-builder/install-openmpi.sh'
assert_contains "${ROOT_DIR}/scripts/common/third-party-registry.sh" '/toolkit/docker/cuda-builder/install-hdf5.sh'
assert_contains "${ROOT_DIR}/scripts/common/third-party-registry.sh" '/toolkit/docker/cuda-builder/install-h5engine.sh'
assert_contains "${ROOT_DIR}/scripts/common/third-party-registry.sh" "/bin/bash '/toolkit/docker/cuda-builder/install-eigen3.sh'"
assert_contains "${ROOT_DIR}/scripts/common/third-party-registry.sh" "/bin/bash '/toolkit/docker/cuda-builder/install-openmpi.sh'"
assert_contains "${ROOT_DIR}/scripts/common/third-party-registry.sh" "/bin/bash '/toolkit/docker/cuda-builder/install-hdf5.sh'"
assert_contains "${ROOT_DIR}/scripts/common/third-party-registry.sh" "/bin/bash '/toolkit/docker/cuda-builder/install-h5engine.sh'"
assert_contains "${ROOT_DIR}/scripts/common/third-party-registry.sh" "/bin/bash '/toolkit/docker/cuda-builder/install-muparserx.sh'"
assert_contains "${ROOT_DIR}/scripts/common/third-party-registry.sh" 'third_party_linux_install_command'
assert_contains "${ROOT_DIR}/scripts/common/third-party-registry.sh" 'third_party_windows_install_function'
assert_contains "${ROOT_DIR}/docker-compose.yml" 'CUDA_CXX_DEPS_ROOT'
assert_contains "${ROOT_DIR}/docker-compose.yml" 'CUDA_CXX_RUN_UID'
assert_contains "${ROOT_DIR}/docker-compose.yml" 'CUDA_CXX_RUN_GID'
assert_contains "${ROOT_DIR}/docker-compose.yml" 'user: "${CUDA_CXX_RUN_UID}:${CUDA_CXX_RUN_GID}"'
assert_contains "${ROOT_DIR}/docker-compose.yml" 'HOME: /tmp/cuda-cxx-home'
assert_contains "${ROOT_DIR}/docker-compose.yml" 'CCACHE_DIR: /tmp/cuda-cxx-home/.ccache'
assert_contains "${ROOT_DIR}/docker-compose.yml" 'mkdir -p "$$CCACHE_DIR"'
assert_service_block_not_contains "  cuda-cxx-centos7:" "  cuda-cxx-deps-centos7:" 'export CHRONO_ROOT='
assert_service_block_not_contains "  cuda-cxx-centos7:" "  cuda-cxx-deps-centos7:" 'export EIGEN3_ROOT='
assert_service_block_not_contains "  cuda-cxx-centos7:" "  cuda-cxx-deps-centos7:" 'export HDF5_ROOT='
assert_service_block_not_contains "  cuda-cxx-centos7:" "  cuda-cxx-deps-centos7:" 'export MUPARSERX_ROOT='
assert_service_block_not_contains "  cuda-cxx-centos7:" "  cuda-cxx-deps-centos7:" 'export OPENMPI_ROOT='
assert_service_block_not_contains "  cuda-cxx-centos7:" "  cuda-cxx-deps-centos7:" 'export H5ENGINE_SPH_ROOT='
assert_service_block_not_contains "  cuda-cxx-centos7:" "  cuda-cxx-deps-centos7:" 'export H5ENGINE_DEM_ROOT='
assert_service_block_not_contains "  cuda-cxx-rocky8:" "  cuda-cxx-deps-rocky8:" 'export CHRONO_ROOT='
assert_service_block_not_contains "  cuda-cxx-rocky8:" "  cuda-cxx-deps-rocky8:" 'export EIGEN3_ROOT='
assert_service_block_not_contains "  cuda-cxx-rocky8:" "  cuda-cxx-deps-rocky8:" 'export HDF5_ROOT='
assert_service_block_not_contains "  cuda-cxx-rocky8:" "  cuda-cxx-deps-rocky8:" 'export MUPARSERX_ROOT='
assert_service_block_not_contains "  cuda-cxx-rocky8:" "  cuda-cxx-deps-rocky8:" 'export OPENMPI_ROOT='
assert_service_block_not_contains "  cuda-cxx-rocky8:" "  cuda-cxx-deps-rocky8:" 'export H5ENGINE_SPH_ROOT='
assert_service_block_not_contains "  cuda-cxx-rocky8:" "  cuda-cxx-deps-rocky8:" 'export H5ENGINE_DEM_ROOT='
assert_service_block_not_contains "  cuda-cxx-ubuntu2204:" "  cuda-cxx-deps-ubuntu2204:" 'export CHRONO_ROOT='
assert_service_block_not_contains "  cuda-cxx-ubuntu2204:" "  cuda-cxx-deps-ubuntu2204:" 'export EIGEN3_ROOT='
assert_service_block_not_contains "  cuda-cxx-ubuntu2204:" "  cuda-cxx-deps-ubuntu2204:" 'export HDF5_ROOT='
assert_service_block_not_contains "  cuda-cxx-ubuntu2204:" "  cuda-cxx-deps-ubuntu2204:" 'export MUPARSERX_ROOT='
assert_service_block_not_contains "  cuda-cxx-ubuntu2204:" "  cuda-cxx-deps-ubuntu2204:" 'export OPENMPI_ROOT='
assert_service_block_not_contains "  cuda-cxx-ubuntu2204:" "  cuda-cxx-deps-ubuntu2204:" 'export H5ENGINE_SPH_ROOT='
assert_service_block_not_contains "  cuda-cxx-ubuntu2204:" "  cuda-cxx-deps-ubuntu2204:" 'export H5ENGINE_DEM_ROOT='
assert_contains "${ROOT_DIR}/docker-compose.yml" 'CUDA_CXX_PLATFORM_DEPS_ROOT/chrono-install'
assert_contains "${ROOT_DIR}/docker-compose.yml" 'CUDA_CXX_PLATFORM_DEPS_ROOT/eigen3-install'
assert_contains "${ROOT_DIR}/docker-compose.yml" 'CUDA_CXX_PLATFORM_DEPS_ROOT/openmpi-install/bin'
assert_contains "${ROOT_DIR}/docker-compose.yml" 'cuda-cxx-deps-centos7'
assert_contains "${ROOT_DIR}/docker-compose.yml" 'cuda-cxx-deps-rocky8'
assert_contains "${ROOT_DIR}/docker-compose.yml" 'cuda-cxx-deps-ubuntu2204'
assert_contains "${ROOT_DIR}/docker-compose.yml" '/toolkit/docker/cuda-builder/install-eigen3.sh'
assert_contains "${ROOT_DIR}/docker-compose.yml" '/toolkit/docker/cuda-builder/install-openmpi.sh'

assert_contains "${ROOT_DIR}/docker/cuda-builder/centos7.Dockerfile" 'ARG http_proxy'
assert_contains "${ROOT_DIR}/docker/cuda-builder/centos7.Dockerfile" 'ARG HTTP_PROXY'
assert_contains "${ROOT_DIR}/docker/cuda-builder/centos7.Dockerfile" 'YUM_PROXY="${http_proxy:-${HTTP_PROXY}}"'
assert_contains "${ROOT_DIR}/docker/cuda-builder/centos7.Dockerfile" 'echo "proxy=${YUM_PROXY}" >> /etc/yum.conf'
assert_contains "${ROOT_DIR}/docker/cuda-builder/centos7.Dockerfile" 'devtoolset-11-gcc'
assert_contains "${ROOT_DIR}/docker/cuda-builder/centos7.Dockerfile" 'ENV PATH="/opt/rh/devtoolset-11/root/usr/bin:${PATH}"'
assert_contains "${ROOT_DIR}/docker/cuda-builder/rocky8.Dockerfile" 'gcc-toolset-11-gcc-c++'
assert_contains "${ROOT_DIR}/docker/cuda-builder/rocky8.Dockerfile" 'ENV PATH="/opt/rh/gcc-toolset-11/root/usr/bin:${PATH}"'
assert_contains "${ROOT_DIR}/scripts/prepare-chrono-source-cache.sh" 'Usage: scripts/prepare-chrono-source-cache.sh'
assert_contains "${ROOT_DIR}/scripts/prepare-chrono-source-cache.sh" 'exec "${ROOT_DIR}/scripts/prepare-third-party-cache.sh" --deps chrono "$@"'
assert_contains "${ROOT_DIR}/.gitignore" 'docker/cuda-builder/deps/chrono-cache/'
assert_contains "${ROOT_DIR}/.gitignore" 'docker/cuda-builder/deps/chrono-source.tar.gz'
assert_contains "${ROOT_DIR}/.gitignore" 'docker/cuda-builder/deps/eigen3-cache/'
assert_contains "${ROOT_DIR}/.gitignore" 'docker/cuda-builder/deps/openmpi-cache/'
assert_contains "${ROOT_DIR}/.gitignore" 'docker/cuda-builder/deps/eigen-3.4.0.tar.gz'
assert_contains "${ROOT_DIR}/.gitignore" 'docker/cuda-builder/deps/openmpi-4.1.6.tar.gz'
assert_contains "${ROOT_DIR}/.dockerignore" 'docker/cuda-builder/deps/chrono-cache'
assert_contains "${ROOT_DIR}/.dockerignore" 'docker/cuda-builder/deps/eigen3-cache'
assert_contains "${ROOT_DIR}/.dockerignore" 'docker/cuda-builder/deps/openmpi-cache'

echo "build builder image tests passed"
