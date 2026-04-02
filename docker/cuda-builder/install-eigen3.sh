#!/usr/bin/env bash
set -euo pipefail

: "${EIGEN3_VERSION:=3.4.0}"
: "${DEPS_ROOT:=${HOME}/deps}"
: "${EIGEN3_PREFIX:=}"
: "${EIGEN3_INSTALL_PREFIX:=${DEPS_ROOT}/eigen3-install}"
: "${EIGEN3_BUILD_PARALLEL:=${CHRONO_BUILD_PARALLEL:-6}}"
: "${EIGEN3_ARCHIVE:=/tmp/deps/eigen-3.4.0.tar.gz}"

if [[ -n "${EIGEN3_PREFIX}" ]]; then
  EIGEN3_INSTALL_PREFIX="${EIGEN3_PREFIX}"
fi

ARCHIVE="eigen-${EIGEN3_VERSION}.tar.gz"
SOURCE_DIR="$(dirname "${DEPS_ROOT}")/eigen-${EIGEN3_VERSION}"
BUILD_DIR="${SOURCE_DIR}/build"
URL="https://gitlab.com/libeigen/eigen/-/archive/${EIGEN3_VERSION}/${ARCHIVE}"
VERSION_MARKER="${EIGEN3_INSTALL_PREFIX}/.eigen3-source-version"
ARCHIVE_PATH="${EIGEN3_ARCHIVE}"

mkdir -p "$(dirname "${SOURCE_DIR}")" "${EIGEN3_INSTALL_PREFIX}"

if [[ -f "${VERSION_MARKER}" ]] && \
   grep -Fxq "${EIGEN3_VERSION}" "${VERSION_MARKER}" && \
   [[ -f "${EIGEN3_INSTALL_PREFIX}/include/eigen3/Eigen/Core" ]]; then
  exit 0
fi

if test -f "${EIGEN3_ARCHIVE}"; then
  ARCHIVE_PATH="${EIGEN3_ARCHIVE}"
else
  ARCHIVE_PATH="/tmp/${ARCHIVE}"
  curl -fsSL "${URL}" -o "${ARCHIVE_PATH}"
fi

test -f "${ARCHIVE_PATH}"
rm -rf "${SOURCE_DIR}"
tar --no-same-owner --no-same-permissions -xzf "${ARCHIVE_PATH}" -C "$(dirname "${SOURCE_DIR}")" -m

cmake -S "${SOURCE_DIR}" -B "${BUILD_DIR}" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="${EIGEN3_INSTALL_PREFIX}" \
  -DBUILD_TESTING=OFF

cmake --build "${BUILD_DIR}" --parallel "${EIGEN3_BUILD_PARALLEL}"
cmake --install "${BUILD_DIR}"

printf '%s\n' "${EIGEN3_VERSION}" > "${VERSION_MARKER}"
test -f "${EIGEN3_INSTALL_PREFIX}/include/eigen3/Eigen/Core"
