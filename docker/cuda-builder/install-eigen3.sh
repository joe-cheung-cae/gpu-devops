#!/usr/bin/env bash
set -euo pipefail

: "${EIGEN3_VERSION:=3.4.0}"
: "${DEPS_ROOT:=${HOME}/deps}"
: "${EIGEN3_PREFIX:=}"
: "${EIGEN3_INSTALL_PREFIX:=${DEPS_ROOT}/eigen3-install}"
: "${EIGEN3_BUILD_PARALLEL:=${CHRONO_BUILD_PARALLEL:-6}}"
: "${EIGEN3_ARCHIVE:=$(dirname "${DEPS_ROOT}")/cache/eigen-3.4.0.tar.gz}"

if [[ -n "${EIGEN3_PREFIX}" ]]; then
  EIGEN3_INSTALL_PREFIX="${EIGEN3_PREFIX}"
fi

SOURCE_DIR="$(dirname "${DEPS_ROOT}")/eigen-${EIGEN3_VERSION}"
BUILD_DIR="${SOURCE_DIR}/build"
VERSION_MARKER="${EIGEN3_INSTALL_PREFIX}/.eigen3-source-version"

mkdir -p "$(dirname "${SOURCE_DIR}")" "${EIGEN3_INSTALL_PREFIX}"

if [[ -f "${VERSION_MARKER}" ]] && \
   grep -Fxq "${EIGEN3_VERSION}" "${VERSION_MARKER}" && \
   [[ -f "${EIGEN3_INSTALL_PREFIX}/include/eigen3/Eigen/Core" ]]; then
  exit 0
fi

if [[ ! -f "${EIGEN3_ARCHIVE}" ]]; then
  echo "Expected archive to exist: ${EIGEN3_ARCHIVE}" >&2
  exit 1
fi

rm -rf "${SOURCE_DIR}"
tar --no-same-owner --no-same-permissions -xzf "${EIGEN3_ARCHIVE}" -C "$(dirname "${SOURCE_DIR}")" -m

cmake -S "${SOURCE_DIR}" -B "${BUILD_DIR}" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="${EIGEN3_INSTALL_PREFIX}" \
  -DBUILD_TESTING=OFF

cmake --build "${BUILD_DIR}" --parallel "${EIGEN3_BUILD_PARALLEL}"
cmake --install "${BUILD_DIR}"

printf '%s\n' "${EIGEN3_VERSION}" > "${VERSION_MARKER}"
test -f "${EIGEN3_INSTALL_PREFIX}/include/eigen3/Eigen/Core"
