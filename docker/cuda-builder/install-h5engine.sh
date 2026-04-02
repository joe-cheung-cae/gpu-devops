#!/usr/bin/env bash
set -euo pipefail

: "${DEPS_ROOT:=${HOME}/deps}"
: "${HDF5_INSTALL_PREFIX:=${DEPS_ROOT}/hdf5-install}"
: "${H5ENGINE_BUILD_PARALLEL:=${CHRONO_BUILD_PARALLEL:-6}}"
: "${H5ENGINE_OUTPUT_ROOT:=${DEPS_ROOT}}"
: "${H5ENGINE_SPH_ARCHIVE:=docker/cuda-builder/deps/h5engine-sph.tar.gz}"
: "${H5ENGINE_DEM_ARCHIVE:=docker/cuda-builder/deps/h5engine-dem.tar.gz}"

test -f "${HDF5_INSTALL_PREFIX}/lib/libhdf5.so"

resolve_archive_path() {
  local archive_path="$1"
  if [[ -f "${archive_path}" ]]; then
    printf '%s\n' "${archive_path}"
  else
    printf '/tmp/%s\n' "$(basename "${archive_path}")"
  fi
}

copy_hdf5_runtime() {
  local package_dir="$1"

  mkdir -p "${package_dir}/third/hdf5/include/linux" "${package_dir}/third/hdf5/lib/linux"
  rm -rf "${package_dir}/third/hdf5/include/linux"/*
  cp -a "${HDF5_INSTALL_PREFIX}/include/." "${package_dir}/third/hdf5/include/linux/"
  rm -rf "${package_dir}/third/hdf5/lib/linux"/*
  cp -a "${HDF5_INSTALL_PREFIX}/lib/libhdf5.so"* "${package_dir}/third/hdf5/lib/linux/"
}

build_package() {
  local package_name="$1"
  local archive_path="$2"
  local package_dir="${H5ENGINE_OUTPUT_ROOT}/${package_name}"
  local version_marker="${package_dir}/.h5engine-source-version"

  archive_path="$(resolve_archive_path "${archive_path}")"
  test -f "${archive_path}"

  if [[ -f "${version_marker}" ]] && \
     grep -Fxq "$(basename "${archive_path}")" "${version_marker}" && \
     [[ -f "${package_dir}/build/h5Engine/libh5Engine.so" ]] && \
     [[ -x "${package_dir}/build/testHdf5" ]]; then
    return 0
  fi

  rm -rf "${package_dir}"
  mkdir -p "${H5ENGINE_OUTPUT_ROOT}"
  tar --no-same-owner --no-same-permissions -xzf "${archive_path}" -C "${H5ENGINE_OUTPUT_ROOT}" -m

  test -d "${package_dir}"
  copy_hdf5_runtime "${package_dir}"

  rm -rf "${package_dir}/build"
  mkdir -p "${package_dir}/build"
  (
    cd "${package_dir}/build"
    cmake .. -DCMAKE_BUILD_TYPE=Release
    make -j"${H5ENGINE_BUILD_PARALLEL}"
  )
  (
    cd "${package_dir}"
    test -f ./build/h5Engine/libh5Engine.so
    test -x ./build/testHdf5
    ldd ./build/h5Engine/libh5Engine.so
    ./build/testHdf5
  )
  printf '%s\n' "$(basename "${archive_path}")" > "${version_marker}"
}

build_package "h5engine-sph" "${H5ENGINE_SPH_ARCHIVE}"
build_package "h5engine-dem" "${H5ENGINE_DEM_ARCHIVE}"
