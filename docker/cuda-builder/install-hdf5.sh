#!/usr/bin/env bash
set -euo pipefail

: "${DEPS_ROOT:=${HOME}/deps}"
: "${HDF5_ARCHIVE:=docker/cuda-builder/deps/CMake-hdf5-1.14.1-2.tar.gz}"
: "${HDF5_INSTALL_PREFIX:=${DEPS_ROOT}/hdf5-install}"
: "${HDF5_BUILD_PARALLEL:=${CHRONO_BUILD_PARALLEL:-6}}"

ARCHIVE_PATH="${HDF5_ARCHIVE}"
EXTRACT_ROOT="/tmp/CMake-hdf5-1.14.1-2"
SOURCE_DIR="${EXTRACT_ROOT}/CMake-hdf5-1.14.1-2/hdf5-1.14.1-2"
VERSION_MARKER="${HDF5_INSTALL_PREFIX}/.hdf5-source-version"
HDF5_SOURCE_VERSION="1.14.1-2"

if [[ ! -f "${ARCHIVE_PATH}" ]]; then
  ARCHIVE_PATH="/tmp/$(basename "${HDF5_ARCHIVE}")"
fi

test -f "${ARCHIVE_PATH}"
mkdir -p "${HDF5_INSTALL_PREFIX}"

if [[ -f "${VERSION_MARKER}" ]] && \
   grep -Fxq "${HDF5_SOURCE_VERSION}" "${VERSION_MARKER}" && \
   [[ -f "${HDF5_INSTALL_PREFIX}/lib/libhdf5.so" ]] && \
   [[ -x "${HDF5_INSTALL_PREFIX}/bin/h5cc" ]]; then
  ldd "${HDF5_INSTALL_PREFIX}/lib/libhdf5.so"
  exit 0
fi

rm -rf "${EXTRACT_ROOT}"
mkdir -p "${EXTRACT_ROOT}"
tar --no-same-owner --no-same-permissions -xzf "${ARCHIVE_PATH}" -C "${EXTRACT_ROOT}" -m

cd "${SOURCE_DIR}"
./configure --prefix="${HDF5_INSTALL_PREFIX}"
make -j"${HDF5_BUILD_PARALLEL}"
make install

printf '%s\n' "${HDF5_SOURCE_VERSION}" > "${VERSION_MARKER}"
test -f "${HDF5_INSTALL_PREFIX}/lib/libhdf5.so"
ldd "${HDF5_INSTALL_PREFIX}/lib/libhdf5.so"
