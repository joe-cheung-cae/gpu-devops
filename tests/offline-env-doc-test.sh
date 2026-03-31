#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOC_PATH="${ROOT_DIR}/docs/offline-env-configuration.md"

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
    fail "missing expected content"
  fi
}

[[ -f "${DOC_PATH}" ]] || fail "expected file to exist: ${DOC_PATH}"

assert_contains "${DOC_PATH}" "HOST_PROJECT_DIR"
assert_contains "${DOC_PATH}" "CUDA_CXX_BUILD_ROOT"
assert_contains "${DOC_PATH}" "CUDA_CXX_INSTALL_ROOT"
assert_contains "${DOC_PATH}" "RUNNER_TLS_CA_FILE"
assert_contains "${DOC_PATH}" "Docker executor"
assert_contains "${DOC_PATH}" "shell runner"
assert_contains "${DOC_PATH}" ".gpu-devops/.env"

echo "offline env doc tests passed"
