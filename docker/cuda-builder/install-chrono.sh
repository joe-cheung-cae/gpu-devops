#!/usr/bin/env bash
set -euo pipefail

: "${DEPS_ROOT:=${HOME}/deps}"
: "${CHRONO_SOURCE_DIR:=${DEPS_ROOT}/chrono}"
: "${CHRONO_BUILD_DIR:=${CHRONO_SOURCE_DIR}/build}"
: "${CHRONO_INSTALL_PREFIX:=${DEPS_ROOT}/chrono-install}"
: "${CHRONO_BUILD_PARALLEL:=6}"
: "${CHRONO_ARCHIVE:=$(dirname "${DEPS_ROOT}")/cache/chrono-source.tar.gz}"
: "${CHRONO_CMAKE_GENERATOR:=Ninja}"

mkdir -p "$(dirname "${CHRONO_SOURCE_DIR}")" "${CHRONO_INSTALL_PREFIX}"

if [[ -f "${CHRONO_INSTALL_PREFIX}/.chrono-source-ref" ]] && \
   [[ -f "${CHRONO_INSTALL_PREFIX}/lib/libChronoEngine.so" ]]; then
  ldd "${CHRONO_INSTALL_PREFIX}/lib/libChronoEngine.so"
  exit 0
fi

if [[ ! -f "${CHRONO_ARCHIVE}" ]]; then
  echo "Expected archive to exist: ${CHRONO_ARCHIVE}" >&2
  exit 1
fi

rm -rf "${CHRONO_SOURCE_DIR}"
mkdir -p "${CHRONO_SOURCE_DIR}"
tar -xzf "${CHRONO_ARCHIVE}" -C "${CHRONO_SOURCE_DIR}"

if [[ -f "${CHRONO_SOURCE_DIR}/.chrono-source-ref" ]]; then
  CHRONO_SOURCE_REF="$(< "${CHRONO_SOURCE_DIR}/.chrono-source-ref")"
else
  CHRONO_SOURCE_REF="$(basename "${CHRONO_ARCHIVE}")"
fi
printf '%s\n' "${CHRONO_SOURCE_REF}" > "${CHRONO_SOURCE_DIR}/.chrono-source-ref"
printf '%s\n' "${CHRONO_SOURCE_REF}" > "${CHRONO_INSTALL_PREFIX}/.chrono-source-ref"

CHRONO_CMAKELISTS="${CHRONO_SOURCE_DIR}/src/chrono/CMakeLists.txt" python3 - <<'PY'
import os
from pathlib import Path

cmake_path = Path(os.environ["CHRONO_CMAKELISTS"])
text = cmake_path.read_text()
needle = 'target_link_libraries(ChronoEngine -static-libgcc -static-libstdc++)'
insert_after = 'target_link_libraries(ChronoEngine ${OPENMP_LIBRARIES} ${CH_SOCKET_LIB})'

if needle not in text:
    if insert_after not in text:
        raise SystemExit(f"Missing anchor in {cmake_path}")
    text = text.replace(insert_after, f"{insert_after}\n{needle}", 1)
    cmake_path.write_text(text)
PY

mkdir -p "${CHRONO_BUILD_DIR}"
cd "${CHRONO_BUILD_DIR}"

cmake -G "${CHRONO_CMAKE_GENERATOR}" .. \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_BENCHMARKING=OFF \
  -DBUILD_DEMOS=OFF \
  -DBUILD_TESTING=OFF \
  -DUSE_BULLET_DOUBLE=ON \
  -DUSE_SIMD=OFF \
  -DCMAKE_INSTALL_PREFIX="${CHRONO_INSTALL_PREFIX}"

cmake --build . --parallel "${CHRONO_BUILD_PARALLEL}"
cmake --install .

ldd "${CHRONO_INSTALL_PREFIX}/lib/libChronoEngine.so"
