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
assert_contains "${DOC_PATH}" "CUDA_CXX_DEPS_ROOT"
assert_contains "${DOC_PATH}" "RUNNER_TLS_CA_FILE"
assert_contains "${DOC_PATH}" "shell runner"
assert_contains "${DOC_PATH}" ".gpu-devops/.env"
assert_contains "${DOC_PATH}" "prepare-builder-deps.sh"
assert_contains "${DOC_PATH}" "rootless Docker"
assert_contains "${DOC_PATH}" "dockerd-rootless-setuptool.sh install"
assert_contains "${DOC_PATH}" "/etc/subuid"
assert_contains "${DOC_PATH}" "/etc/subgid"
assert_contains "${DOC_PATH}" "systemctl --user enable docker"
assert_contains "${DOC_PATH}" "loginctl enable-linger"
assert_contains "${DOC_PATH}" "DOCKER_HOST=unix:///run/user/"
assert_contains "${DOC_PATH}" "CUDA_CXX_ALLOW_ROOTFUL_DOCKER=1"
if grep -Fq -- "RUNNER_SHELL_EXECUTOR" "${DOC_PATH}"; then
  fail "RUNNER_SHELL_EXECUTOR should not appear in offline env doc"
fi
if grep -Fq -- "SHELL_RUNNER_DEFAULT_PLATFORM" "${DOC_PATH}"; then
  fail "SHELL_RUNNER_DEFAULT_PLATFORM should not appear in offline env doc"
fi

echo "offline env doc tests passed"
