#!/usr/bin/env bash
set -euo pipefail

: "${CHRONO_GIT_URL:=https://github.com/projectchrono/chrono.git}"
: "${CHRONO_GIT_REF:=3eb56218b}"
: "${CHRONO_SOURCE_DIR:=${HOME}/deps/chrono}"
: "${CHRONO_BUILD_DIR:=${CHRONO_SOURCE_DIR}/build}"
: "${CHRONO_INSTALL_PREFIX:=${HOME}/deps/chrono-install}"
: "${CHRONO_BUILD_PARALLEL:=6}"

mkdir -p "$(dirname "${CHRONO_SOURCE_DIR}")" "${CHRONO_INSTALL_PREFIX}"

if [[ ! -d "${CHRONO_SOURCE_DIR}/.git" ]]; then
  git clone "${CHRONO_GIT_URL}" "${CHRONO_SOURCE_DIR}"
fi

(
  cd "${CHRONO_SOURCE_DIR}"
  git fetch --all --tags
  git checkout --force "${CHRONO_GIT_REF}"
)

CHRONO_CMAKELISTS="${CHRONO_SOURCE_DIR}/src/chrono/CMakeLists.txt" python3 - <<'PY'
import os
from pathlib import Path

cmake_path = Path(os.environ["CHRONO_CMAKELISTS"])
needle = 'target_link_libraries(ChronoEngine -static-libgcc -static-libstdc++)'
text = cmake_path.read_text()
if needle not in text:
    insert_after = 'target_link_libraries(ChronoEngine ${OPENMP_LIBRARIES} ${CH_SOCKET_LIB})'
    if insert_after not in text:
        raise SystemExit(f"Missing anchor in {cmake_path}")
    text = text.replace(insert_after, f"{insert_after}\n{needle}", 1)
    cmake_path.write_text(text)
PY

mkdir -p "${CHRONO_BUILD_DIR}"
cd "${CHRONO_BUILD_DIR}"

cmake .. \
  -DCMAKE_BUILD_TYPE=Release \
  -DUSE_BULLET_DOUBLE=ON \
  -DUSE_SIMD=OFF \
  -DCMAKE_INSTALL_PREFIX="${CHRONO_INSTALL_PREFIX}"

cmake --build . --parallel "${CHRONO_BUILD_PARALLEL}"
cmake --install .

ldd "${CHRONO_INSTALL_PREFIX}/lib/libChronoEngine.so"
