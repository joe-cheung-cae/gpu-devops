#!/usr/bin/env bash
set -euo pipefail

: "${MUPARSERX_GIT_URL:=https://github.com/joe-cheung-cae/muparserx.git}"
: "${MUPARSERX_GIT_BRANCH:=master}"
: "${MUPARSERX_SOURCE_DIR:=${HOME}/deps/muparserx}"
: "${MUPARSERX_BUILD_DIR:=${MUPARSERX_SOURCE_DIR}/build}"
: "${MUPARSERX_INSTALL_PREFIX:=${HOME}/deps/muparserx-install}"
: "${MUPARSERX_BUILD_PARALLEL:=${CHRONO_BUILD_PARALLEL:-6}}"

mkdir -p "$(dirname "${MUPARSERX_SOURCE_DIR}")" "${MUPARSERX_INSTALL_PREFIX}"

if [[ ! -d "${MUPARSERX_SOURCE_DIR}/.git" ]]; then
  git clone "${MUPARSERX_GIT_URL}" "${MUPARSERX_SOURCE_DIR}"
fi

(
  cd "${MUPARSERX_SOURCE_DIR}"
  git fetch origin "${MUPARSERX_GIT_BRANCH}"
  git checkout --force "${MUPARSERX_GIT_BRANCH}"
  git reset --hard "origin/${MUPARSERX_GIT_BRANCH}"
)

mkdir -p "${MUPARSERX_BUILD_DIR}"
(
  cd "${MUPARSERX_BUILD_DIR}"
  cmake .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="${MUPARSERX_INSTALL_PREFIX}"
  make -j"${MUPARSERX_BUILD_PARALLEL}"
  cmake --install .
)

test -f "${MUPARSERX_BUILD_DIR}/libmuparserx.so"
(
  cd "${MUPARSERX_SOURCE_DIR}"
  ldd build/libmuparserx.so
)
