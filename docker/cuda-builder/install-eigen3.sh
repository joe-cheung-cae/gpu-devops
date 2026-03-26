#!/usr/bin/env bash
set -euo pipefail

: "${EIGEN3_VERSION:=3.4.0}"
: "${EIGEN3_PREFIX:=/usr/local}"

ARCHIVE="eigen-${EIGEN3_VERSION}.tar.gz"
SOURCE_DIR="/tmp/eigen-${EIGEN3_VERSION}"
BUILD_DIR="${SOURCE_DIR}/build"
URL="https://gitlab.com/libeigen/eigen/-/archive/${EIGEN3_VERSION}/${ARCHIVE}"

curl -fsSL "${URL}" -o "/tmp/${ARCHIVE}"
tar -xzf "/tmp/${ARCHIVE}" -C /tmp

cmake -S "${SOURCE_DIR}" -B "${BUILD_DIR}" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="${EIGEN3_PREFIX}" \
  -DBUILD_TESTING=OFF

cmake --build "${BUILD_DIR}" --parallel "$(getconf _NPROCESSORS_ONLN)"
cmake --install "${BUILD_DIR}"

rm -rf "${SOURCE_DIR}" "/tmp/${ARCHIVE}"
