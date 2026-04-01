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
printf '%s\n' "$*" >> "${TEST_LOG_FILE:?}"
exit 0
EOF
chmod +x "${MOCK_BIN}/docker"

ENV_FILE="${TMP_DIR}/.env"
HOST_PROJECT_DIR="${TMP_DIR}/project"
mkdir -p "${HOST_PROJECT_DIR}"
cat > "${ENV_FILE}" <<'EOF'
BUILDER_IMAGE_FAMILY=registry.local/devops/cuda-builder:cuda11.7-cmake3.26
BUILDER_DEFAULT_PLATFORM=centos7
BUILDER_PLATFORMS=centos7,rocky8,ubuntu2204
BUILDER_IMAGE=registry.local/devops/cuda-builder:cuda11.7-cmake3.26-centos7
HOST_PROJECT_DIR=__HOST_PROJECT_DIR__
CUDA_CXX_DEPS_ROOT=.gpu-devops/artifacts/deps
EOF
sed -i "s#__HOST_PROJECT_DIR__#${HOST_PROJECT_DIR}#" "${ENV_FILE}"

run_prepare() {
  local log_file="$1"
  local stdout_file="$2"
  shift 2
  TEST_LOG_FILE="${log_file}" PATH="${MOCK_BIN}:${PATH}" \
    "${ROOT_DIR}/scripts/prepare-builder-deps.sh" --env-file "${ENV_FILE}" "$@" > "${stdout_file}"
}

default_log="${TMP_DIR}/default.log"
default_stdout="${TMP_DIR}/default.stdout"
run_prepare "${default_log}" "${default_stdout}" --platform centos7
assert_contains "${default_log}" "run --rm"
assert_contains "${default_log}" "registry.local/devops/cuda-builder:cuda11.7-cmake3.26-centos7"
assert_contains "${default_log}" "${HOST_PROJECT_DIR}:/workspace"
assert_contains "${default_log}" "${ROOT_DIR}:/toolkit"
assert_contains "${default_log}" "CUDA_CXX_DEPS_ROOT=.gpu-devops/artifacts/deps"
assert_contains "${default_log}" "DEPS_ROOT=/workspace/.gpu-devops/artifacts/deps/centos7"
assert_contains "${default_log}" "CHRONO_ARCHIVE=/toolkit/docker/cuda-builder/deps/chrono-source.tar.gz"
assert_contains "${default_log}" "/toolkit/docker/cuda-builder/install-chrono.sh"
assert_contains "${default_log}" "/toolkit/docker/cuda-builder/install-hdf5.sh"
assert_contains "${default_log}" "/toolkit/docker/cuda-builder/install-h5engine.sh"
assert_contains "${default_log}" "/toolkit/docker/cuda-builder/install-muparserx.sh"
assert_contains "${default_stdout}" "[1/5] Loading environment"
assert_contains "${default_stdout}" "[5/5] Prepared builder dependency cache"
assert_contains "${default_stdout}" "Dependencies: chrono,hdf5,h5engine,muparserx"

subset_log="${TMP_DIR}/subset.log"
subset_stdout="${TMP_DIR}/subset.stdout"
run_prepare "${subset_log}" "${subset_stdout}" --platform rocky8 --deps chrono,muparserx
assert_contains "${subset_log}" "registry.local/devops/cuda-builder:cuda11.7-cmake3.26-rocky8"
assert_contains "${subset_log}" "/toolkit/docker/cuda-builder/install-chrono.sh"
assert_contains "${subset_log}" "/toolkit/docker/cuda-builder/install-muparserx.sh"
assert_not_contains "${subset_log}" "/toolkit/docker/cuda-builder/install-hdf5.sh"
assert_not_contains "${subset_log}" "/toolkit/docker/cuda-builder/install-h5engine.sh"
assert_contains "${subset_stdout}" "Dependencies: chrono,muparserx"

assert_file_exists "${ROOT_DIR}/scripts/prepare-builder-deps.sh"

echo "prepare builder deps tests passed"
