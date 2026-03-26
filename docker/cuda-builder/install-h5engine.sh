#!/usr/bin/env bash
set -euo pipefail

: "${HDF5_INSTALL_PREFIX:=${HOME}/deps/hdf5-install}"
: "${H5ENGINE_BUILD_PARALLEL:=${CHRONO_BUILD_PARALLEL:-6}}"
: "${H5ENGINE_SPH_ARCHIVE:=docker/cuda-builder/deps/h5engine-sph.tar.gz}"
: "${H5ENGINE_DEM_ARCHIVE:=docker/cuda-builder/deps/h5engine-dem.tar.gz}"

test -f "${HOME}/deps/hdf5-install/lib/libhdf5.so"

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
  local package_dir="${HOME}/deps/${package_name}"

  test -f "${archive_path}"
  rm -rf "${package_dir}"
  mkdir -p "${HOME}/deps"
  tar -xzf "${archive_path}" -C "${HOME}/deps"

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
}

build_package "h5engine-sph" "/tmp/$(basename "${H5ENGINE_SPH_ARCHIVE}")"
build_package "h5engine-dem" "/tmp/$(basename "${H5ENGINE_DEM_ARCHIVE}")"
