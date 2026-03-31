#!/usr/bin/env bash
set -euo pipefail

: "${OPENMPI_VERSION:=4.1.6}"
: "${OPENMPI_PREFIX:=/opt/openmpi}"

ARCHIVE="openmpi-${OPENMPI_VERSION}.tar.gz"
SOURCE_DIR="/tmp/openmpi-${OPENMPI_VERSION}"
URL="https://download.open-mpi.org/release/open-mpi/v4.1/${ARCHIVE}"

curl -fsSL "${URL}" -o "/tmp/${ARCHIVE}"
tar -xzf "/tmp/${ARCHIVE}" -C /tmp
cd "${SOURCE_DIR}"

./configure \
  --prefix="${OPENMPI_PREFIX}" \
  --enable-mpi-cxx \
  --disable-mpi-fortran \
  --enable-static \
  --enable-shared \
  --with-hwloc=internal \
  --with-libevent=internal \
  --with-pmix=internal

make -j"$(getconf _NPROCESSORS_ONLN)"
make install

cd /
rm -rf "${SOURCE_DIR}" "/tmp/${ARCHIVE}"
