#!/usr/bin/env bash
set -euo pipefail

: "${OPENMPI_VERSION:=4.1.6}"
: "${DEPS_ROOT:=${HOME}/deps}"
: "${OPENMPI_PREFIX:=}"
: "${OPENMPI_INSTALL_PREFIX:=${DEPS_ROOT}/openmpi-install}"
: "${OPENMPI_BUILD_PARALLEL:=${CHRONO_BUILD_PARALLEL:-6}}"
: "${OPENMPI_ARCHIVE:=/tmp/deps/openmpi-4.1.6.tar.gz}"

if [[ -n "${OPENMPI_PREFIX}" ]]; then
  OPENMPI_INSTALL_PREFIX="${OPENMPI_PREFIX}"
fi

ARCHIVE="openmpi-${OPENMPI_VERSION}.tar.gz"
SOURCE_DIR="$(dirname "${DEPS_ROOT}")/openmpi-${OPENMPI_VERSION}"
URL="https://download.open-mpi.org/release/open-mpi/v4.1/${ARCHIVE}"
VERSION_MARKER="${OPENMPI_INSTALL_PREFIX}/.openmpi-source-version"
ARCHIVE_PATH="${OPENMPI_ARCHIVE}"

mkdir -p "$(dirname "${SOURCE_DIR}")" "${OPENMPI_INSTALL_PREFIX}"

if [[ -f "${VERSION_MARKER}" ]] && \
   grep -Fxq "${OPENMPI_VERSION}" "${VERSION_MARKER}" && \
   [[ -x "${OPENMPI_INSTALL_PREFIX}/bin/mpicc" ]] && \
   [[ -f "${OPENMPI_INSTALL_PREFIX}/lib/libmpi.a" ]]; then
  exit 0
fi

if test -f "${OPENMPI_ARCHIVE}"; then
  ARCHIVE_PATH="${OPENMPI_ARCHIVE}"
else
  ARCHIVE_PATH="/tmp/${ARCHIVE}"
  curl -fsSL "${URL}" -o "${ARCHIVE_PATH}"
fi

test -f "${ARCHIVE_PATH}"
rm -rf "${SOURCE_DIR}"
tar -xzf "${ARCHIVE_PATH}" -C "$(dirname "${SOURCE_DIR}")"
cd "${SOURCE_DIR}"

./configure \
  --prefix="${OPENMPI_INSTALL_PREFIX}" \
  --enable-mpi-cxx \
  --disable-mpi-fortran \
  --enable-static \
  --enable-shared \
  --with-hwloc=internal \
  --with-libevent=internal \
  --with-pmix=internal

make -j"${OPENMPI_BUILD_PARALLEL}"
make install

printf '%s\n' "${OPENMPI_VERSION}" > "${VERSION_MARKER}"
test -x "${OPENMPI_INSTALL_PREFIX}/bin/mpicc"
test -f "${OPENMPI_INSTALL_PREFIX}/lib/libmpi.a"
