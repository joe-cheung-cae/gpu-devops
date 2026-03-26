#!/usr/bin/env bash
set -euo pipefail

: "${HDF5_ARCHIVE:=docker/cuda-builder/deps/CMake-hdf5-1.14.1-2.tar.gz}"
: "${HDF5_INSTALL_PREFIX:=/root/deps/hdf5-install}"
: "${HDF5_BUILD_PARALLEL:=${CHRONO_BUILD_PARALLEL:-6}}"

ARCHIVE_PATH="/tmp/$(basename "${HDF5_ARCHIVE}")"
EXTRACT_ROOT="/tmp/CMake-hdf5-1.14.1-2"
SOURCE_DIR="${EXTRACT_ROOT}/hdf5-1.14.1-2"

test -f "${ARCHIVE_PATH}"
mkdir -p "${HDF5_INSTALL_PREFIX}"
rm -rf "${EXTRACT_ROOT}"
tar -xzf "${ARCHIVE_PATH}" -C /tmp

cd "${SOURCE_DIR}"
./configure --prefix=/root/deps/hdf5-install
make -j"${HDF5_BUILD_PARALLEL}"
make install

test -f "${HDF5_INSTALL_PREFIX}/lib/libhdf5.so"
ldd "${HDF5_INSTALL_PREFIX}/lib/libhdf5.so"
