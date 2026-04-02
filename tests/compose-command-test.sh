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
if [[ "$1" == "compose" ]] && [[ "$2" == "version" ]]; then
  exit 0
fi
printf '%s\n' "$*" >> "${TEST_LOG_FILE:?}"
printf 'CUDA_CXX_RUN_UID=%s\n' "${CUDA_CXX_RUN_UID:-}" >> "${TEST_ENV_FILE:?}"
printf 'CUDA_CXX_RUN_GID=%s\n' "${CUDA_CXX_RUN_GID:-}" >> "${TEST_ENV_FILE:?}"
exit 0
EOF
chmod +x "${MOCK_BIN}/docker"

LOG_FILE="${TMP_DIR}/docker.log"
ENV_LOG_FILE="${TMP_DIR}/env.log"
TEST_LOG_FILE="${LOG_FILE}" TEST_ENV_FILE="${ENV_LOG_FILE}" MOCK_DOCKER_ROOTLESS=1 PATH="${MOCK_BIN}:${PATH}" \
  "${ROOT_DIR}/scripts/compose.sh" config > "${TMP_DIR}/stdout.log"

assert_contains "${LOG_FILE}" "compose"
assert_contains "${LOG_FILE}" "-f ${ROOT_DIR}/docker-compose.yml config"
assert_not_contains "${ENV_LOG_FILE}" "CUDA_CXX_RUN_UID=$(id -u)"
assert_not_contains "${ENV_LOG_FILE}" "CUDA_CXX_RUN_GID=$(id -g)"

set +e
TEST_LOG_FILE="${TMP_DIR}/rootful.log" TEST_ENV_FILE="${TMP_DIR}/rootful.env" PATH="${MOCK_BIN}:${PATH}" \
  "${ROOT_DIR}/scripts/compose.sh" config > "${TMP_DIR}/rootful.stdout" 2> "${TMP_DIR}/rootful.stderr"
status=$?
set -e
if [[ ${status} -eq 0 ]]; then
  fail "compose.sh should reject non-rootless docker by default"
fi
assert_contains "${TMP_DIR}/rootful.stderr" "Rootless Docker is required"
assert_contains "${TMP_DIR}/rootful.stderr" "CUDA_CXX_ALLOW_ROOTFUL_DOCKER=1"

TEST_LOG_FILE="${TMP_DIR}/override.log" TEST_ENV_FILE="${TMP_DIR}/override.env" CUDA_CXX_ALLOW_ROOTFUL_DOCKER=1 PATH="${MOCK_BIN}:${PATH}" \
  "${ROOT_DIR}/scripts/compose.sh" config > "${TMP_DIR}/override.stdout" 2> "${TMP_DIR}/override.stderr"
assert_contains "${TMP_DIR}/override.stderr" "Proceeding with rootful Docker because CUDA_CXX_ALLOW_ROOTFUL_DOCKER=1"
assert_contains "${TMP_DIR}/override.log" "compose"

echo "compose command tests passed"
