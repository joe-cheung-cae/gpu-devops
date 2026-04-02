#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_contains() {
  local file="$1"
  local expected="$2"
  if ! grep -Fq -- "${expected}" "${file}"; then
    echo "Expected to find: ${expected}" >&2
    echo "In file: ${file}" >&2
    cat "${file}" >&2 || true
    fail "missing expected content"
  fi
}

assert_not_contains() {
  local file="$1"
  local unexpected="$2"
  if grep -Fq -- "${unexpected}" "${file}"; then
    echo "Did not expect to find: ${unexpected}" >&2
    echo "In file: ${file}" >&2
    cat "${file}" >&2 || true
    fail "unexpected content present"
  fi
}

assert_file_exists() {
  local path="$1"
  [[ -f "${path}" ]] || fail "expected file to exist: ${path}"
}

MOCK_BIN="${TMP_DIR}/bin"
mkdir -p "${MOCK_BIN}"

cat > "${MOCK_BIN}/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$1" == "info" ]]; then
  if [[ "${MOCK_DOCKER_ROOTLESS:-0}" == "1" ]]; then
    printf 'name=rootless\n'
  else
    printf 'name=seccomp\n'
  fi
  exit 0
fi
printf '%s\n' "$*" >> "${TEST_LOG_FILE:?}"
exit 0
EOF
chmod +x "${MOCK_BIN}/docker"

ENV_FILE="${TMP_DIR}/.env"
ENV_FILE_DEFAULT="${TMP_DIR}/.env.default"
HOST_PROJECT_DIR="${TMP_DIR}/project"
mkdir -p "${HOST_PROJECT_DIR}"
cat > "${ENV_FILE}" <<'EOF'
BUILDER_IMAGE_FAMILY=registry.local/devops/cuda-builder:cuda11.7-cmake3.26
BUILDER_DEFAULT_PLATFORM=centos7
BUILDER_PLATFORMS=centos7,rocky8,ubuntu2204
BUILDER_IMAGE=registry.local/devops/cuda-builder:cuda11.7-cmake3.26-centos7
HOST_PROJECT_DIR=__HOST_PROJECT_DIR__
CUDA_CXX_THIRD_PARTY_ROOT=.gpu-devops/third_party
EOF
sed -i "s#__HOST_PROJECT_DIR__#${HOST_PROJECT_DIR}#" "${ENV_FILE}"
cat > "${ENV_FILE_DEFAULT}" <<'EOF'
BUILDER_IMAGE_FAMILY=registry.local/devops/cuda-builder:cuda11.7-cmake3.26
BUILDER_DEFAULT_PLATFORM=centos7
BUILDER_PLATFORMS=centos7,rocky8,ubuntu2204
BUILDER_IMAGE=registry.local/devops/cuda-builder:cuda11.7-cmake3.26-centos7
HOST_PROJECT_DIR=__HOST_PROJECT_DIR__
EOF
sed -i "s#__HOST_PROJECT_DIR__#${HOST_PROJECT_DIR}#" "${ENV_FILE_DEFAULT}"

run_prepare() {
  local log_file="$1"
  local stdout_file="$2"
  shift 2
  TEST_LOG_FILE="${log_file}" MOCK_DOCKER_ROOTLESS=1 PATH="${MOCK_BIN}:${PATH}" \
    "${ROOT_DIR}/scripts/prepare-builder-deps.sh" --env-file "${ENV_FILE}" "$@" > "${stdout_file}"
}

default_log="${TMP_DIR}/default.log"
default_stdout="${TMP_DIR}/default.stdout"
run_prepare "${default_log}" "${default_stdout}" --platform centos7
assert_contains "${default_log}" "run --rm"
assert_contains "${default_log}" "registry.local/devops/cuda-builder:cuda11.7-cmake3.26-centos7"
assert_contains "${default_log}" "${HOST_PROJECT_DIR}:/workspace"
assert_contains "${default_log}" "${ROOT_DIR}:/toolkit"
assert_contains "${default_log}" "CUDA_CXX_THIRD_PARTY_ROOT=.gpu-devops/third_party"
assert_contains "${default_log}" "DEPS_ROOT=/workspace/.gpu-devops/third_party/centos7"
assert_contains "${default_log}" "HOME=/tmp/cuda-cxx-home"
assert_contains "${default_log}" "CCACHE_DIR=/tmp/cuda-cxx-home/.ccache"
assert_contains "${default_log}" "CHRONO_ARCHIVE=/workspace/.gpu-devops/third_party/cache/chrono-source.tar.gz"
assert_contains "${default_log}" "mkdir -p '/tmp/cuda-cxx-home/.ccache'"
assert_contains "${default_log}" "/toolkit/docker/cuda-builder/install-chrono.sh"
assert_contains "${default_log}" "/toolkit/docker/cuda-builder/install-eigen3.sh"
assert_contains "${default_log}" "/toolkit/docker/cuda-builder/install-openmpi.sh"
assert_contains "${default_log}" "/toolkit/docker/cuda-builder/install-hdf5.sh"
assert_contains "${default_log}" "/toolkit/docker/cuda-builder/install-h5engine.sh"
assert_contains "${default_log}" "/toolkit/docker/cuda-builder/install-muparserx.sh"
assert_contains "${default_stdout}" "[1/5] Loading environment"
assert_contains "${default_stdout}" "[5/5] Prepared builder dependency cache"
assert_contains "${default_stdout}" "Dependencies: chrono,eigen3,openmpi,hdf5,h5engine,muparserx"
python3 - "${default_log}" <<'PY'
import sys
text = open(sys.argv[1]).read()
needles = [
    "/toolkit/docker/cuda-builder/install-eigen3.sh",
    "/toolkit/docker/cuda-builder/install-openmpi.sh",
    "/toolkit/docker/cuda-builder/install-hdf5.sh",
    "/toolkit/docker/cuda-builder/install-h5engine.sh",
]
positions = [text.index(n) for n in needles]
if positions != sorted(positions):
    raise SystemExit("dependency commands are not emitted in registry order")
PY

subset_log="${TMP_DIR}/subset.log"
subset_stdout="${TMP_DIR}/subset.stdout"
run_prepare "${subset_log}" "${subset_stdout}" --platform rocky8 --deps chrono,muparserx
assert_contains "${subset_log}" "registry.local/devops/cuda-builder:cuda11.7-cmake3.26-rocky8"
assert_contains "${subset_log}" "/workspace/.gpu-devops/third_party/cache/chrono-source.tar.gz"
assert_contains "${subset_log}" "/workspace/.gpu-devops/third_party/cache/muparserx-source.tar.gz"
assert_contains "${subset_log}" "/toolkit/docker/cuda-builder/install-chrono.sh"
assert_contains "${subset_log}" "/toolkit/docker/cuda-builder/install-muparserx.sh"
assert_not_contains "${subset_log}" "/toolkit/docker/cuda-builder/install-hdf5.sh"
assert_not_contains "${subset_log}" "/toolkit/docker/cuda-builder/install-h5engine.sh"
assert_contains "${subset_stdout}" "Dependencies: chrono,muparserx"

toolchain_log="${TMP_DIR}/toolchain.log"
toolchain_stdout="${TMP_DIR}/toolchain.stdout"
run_prepare "${toolchain_log}" "${toolchain_stdout}" --platform ubuntu2204 --deps eigen3,openmpi
assert_contains "${toolchain_log}" "registry.local/devops/cuda-builder:cuda11.7-cmake3.26-ubuntu2204"
assert_contains "${toolchain_log}" "/workspace/.gpu-devops/third_party/cache/eigen-3.4.0.tar.gz"
assert_contains "${toolchain_log}" "/workspace/.gpu-devops/third_party/cache/openmpi-4.1.6.tar.gz"
assert_contains "${toolchain_log}" "/toolkit/docker/cuda-builder/install-eigen3.sh"
assert_contains "${toolchain_log}" "/toolkit/docker/cuda-builder/install-openmpi.sh"
assert_not_contains "${toolchain_log}" "/toolkit/docker/cuda-builder/install-chrono.sh"
assert_contains "${toolchain_stdout}" "Dependencies: eigen3,openmpi"

default_root_log="${TMP_DIR}/default-root.log"
default_root_stdout="${TMP_DIR}/default-root.stdout"
TEST_LOG_FILE="${default_root_log}" MOCK_DOCKER_ROOTLESS=1 PATH="${MOCK_BIN}:${PATH}" \
  "${ROOT_DIR}/scripts/prepare-builder-deps.sh" --env-file "${ENV_FILE_DEFAULT}" --platform centos7 > "${default_root_stdout}"
assert_contains "${default_root_log}" "CUDA_CXX_THIRD_PARTY_ROOT=./third_party"
assert_contains "${default_root_log}" "DEPS_ROOT=/workspace/./third_party/centos7"
assert_contains "${default_root_log}" "CHRONO_ARCHIVE=/workspace/./third_party/cache/chrono-source.tar.gz"

h5engine_log="${TMP_DIR}/h5engine.log"
h5engine_stdout="${TMP_DIR}/h5engine.stdout"
run_prepare "${h5engine_log}" "${h5engine_stdout}" --platform centos7 --deps h5engine
assert_contains "${h5engine_log}" "/workspace/.gpu-devops/third_party/cache/CMake-hdf5-1.14.1-2.tar.gz"
assert_contains "${h5engine_log}" "/workspace/.gpu-devops/third_party/cache/h5engine-sph.tar.gz"
assert_contains "${h5engine_log}" "/workspace/.gpu-devops/third_party/cache/h5engine-dem.tar.gz"
assert_contains "${h5engine_log}" "/toolkit/docker/cuda-builder/install-hdf5.sh"
assert_contains "${h5engine_log}" "/toolkit/docker/cuda-builder/install-h5engine.sh"
python3 - "${h5engine_log}" <<'PY'
import sys
text = open(sys.argv[1]).read()
if text.index("/toolkit/docker/cuda-builder/install-hdf5.sh") > text.index("/toolkit/docker/cuda-builder/install-h5engine.sh"):
    raise SystemExit("hdf5 should be installed before h5engine")
PY
assert_contains "${h5engine_stdout}" "Dependencies: hdf5,h5engine"

set +e
TEST_LOG_FILE="${TMP_DIR}/rootful.log" PATH="${MOCK_BIN}:${PATH}" \
  "${ROOT_DIR}/scripts/prepare-builder-deps.sh" --env-file "${ENV_FILE}" --platform centos7 > "${TMP_DIR}/rootful.stdout" 2> "${TMP_DIR}/rootful.stderr"
status=$?
set -e
if [[ ${status} -eq 0 ]]; then
  fail "prepare-builder-deps.sh should reject non-rootless docker by default"
fi
assert_contains "${TMP_DIR}/rootful.stderr" "Rootless Docker is required"
assert_contains "${TMP_DIR}/rootful.stderr" "CUDA_CXX_ALLOW_ROOTFUL_DOCKER=1"

TEST_LOG_FILE="${TMP_DIR}/override.log" CUDA_CXX_ALLOW_ROOTFUL_DOCKER=1 PATH="${MOCK_BIN}:${PATH}" \
  "${ROOT_DIR}/scripts/prepare-builder-deps.sh" --env-file "${ENV_FILE}" --platform centos7 > "${TMP_DIR}/override.stdout" 2> "${TMP_DIR}/override.stderr"
assert_contains "${TMP_DIR}/override.stderr" "Proceeding with rootful Docker because CUDA_CXX_ALLOW_ROOTFUL_DOCKER=1"
assert_contains "${TMP_DIR}/override.log" "run --rm"

assert_file_exists "${ROOT_DIR}/scripts/prepare-builder-deps.sh"

echo "prepare builder deps tests passed"
