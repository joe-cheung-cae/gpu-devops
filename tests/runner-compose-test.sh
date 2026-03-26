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

run_default_name_test() {
  local output_file="${TMP_DIR}/default-config.yaml"
  docker compose -f "${ROOT_DIR}/runner-compose.yml" config > "${output_file}"
  assert_contains "${output_file}" "container_name: gitlab-runner-devops-docker"
}

run_override_name_test() {
  local output_file="${TMP_DIR}/override-config.yaml"
  RUNNER_CONTAINER_NAME=custom-runner-service \
    docker compose -f "${ROOT_DIR}/runner-compose.yml" config > "${output_file}"
  assert_contains "${output_file}" "container_name: custom-runner-service"
}

run_default_name_test
run_override_name_test

echo "runner compose tests passed"
