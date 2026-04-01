#!/usr/bin/env bash
set -euo pipefail

: "${MUPARSERX_GIT_URL:=https://github.com/joe-cheung-cae/muparserx.git}"
: "${MUPARSERX_GIT_BRANCH:=master}"
: "${DEPS_ROOT:=${HOME}/deps}"
: "${MUPARSERX_SOURCE_DIR:=${DEPS_ROOT}/muparserx}"
: "${MUPARSERX_BUILD_DIR:=${MUPARSERX_SOURCE_DIR}/build}"
: "${MUPARSERX_INSTALL_PREFIX:=${DEPS_ROOT}/muparserx-install}"
: "${MUPARSERX_BUILD_PARALLEL:=${CHRONO_BUILD_PARALLEL:-6}}"
: "${MUPARSERX_ARCHIVE:=/tmp/deps/muparserx-source.tar.gz}"

REF_MARKER="${MUPARSERX_INSTALL_PREFIX}/.muparserx-source-ref"

mkdir -p "$(dirname "${MUPARSERX_SOURCE_DIR}")" "${MUPARSERX_INSTALL_PREFIX}"

if test -f "${MUPARSERX_ARCHIVE}"; then
  rm -rf "${MUPARSERX_SOURCE_DIR}"
  mkdir -p "${MUPARSERX_SOURCE_DIR}"
  tar -xzf "${MUPARSERX_ARCHIVE}" -C "${MUPARSERX_SOURCE_DIR}"
else
  if [[ ! -d "${MUPARSERX_SOURCE_DIR}/.git" ]]; then
    git clone "${MUPARSERX_GIT_URL}" "${MUPARSERX_SOURCE_DIR}"
  fi

  (
    cd "${MUPARSERX_SOURCE_DIR}"
    git fetch origin "${MUPARSERX_GIT_BRANCH}"
    git checkout --force "${MUPARSERX_GIT_BRANCH}"
    git reset --hard "origin/${MUPARSERX_GIT_BRANCH}"
  )
fi

if [[ -f "${MUPARSERX_SOURCE_DIR}/.muparserx-source-ref" ]]; then
  CURRENT_REF="$(< "${MUPARSERX_SOURCE_DIR}/.muparserx-source-ref")"
else
  CURRENT_REF="$(git -C "${MUPARSERX_SOURCE_DIR}" rev-parse HEAD)"
fi
if [[ -f "${REF_MARKER}" ]] && \
   grep -Fxq "${CURRENT_REF}" "${REF_MARKER}" && \
   [[ -f "${MUPARSERX_BUILD_DIR}/libmuparserx.so" ]] && \
   find "${MUPARSERX_INSTALL_PREFIX}/lib" -maxdepth 1 -name 'libmuparserx.so*' | grep -q .; then
  (
    cd "${MUPARSERX_SOURCE_DIR}"
    ldd build/libmuparserx.so
  )
  exit 0
fi

mkdir -p "${MUPARSERX_BUILD_DIR}"
(
  cd "${MUPARSERX_BUILD_DIR}"
  cmake .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="${MUPARSERX_INSTALL_PREFIX}"
  make -j"${MUPARSERX_BUILD_PARALLEL}"
  cmake --install .
)

printf '%s\n' "${CURRENT_REF}" > "${REF_MARKER}"
printf '%s\n' "${CURRENT_REF}" > "${MUPARSERX_SOURCE_DIR}/.muparserx-source-ref"

test -f "${MUPARSERX_BUILD_DIR}/libmuparserx.so"
(
  cd "${MUPARSERX_SOURCE_DIR}"
  ldd build/libmuparserx.so
)
