#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_contains() {
  local text="$1"
  local expected="$2"
  if [[ "${text}" != *"${expected}"* ]]; then
    echo "Expected output to contain: ${expected}" >&2
    echo "Actual output:" >&2
    printf '%s\n' "${text}" >&2
    fail "missing expected content"
  fi
}

run_cmake_version() {
  local image="$1"
  docker run --rm "${image}" cmake --version 2>&1
}

assert_cmake_version() {
  local image="$1"
  local output

  output="$(run_cmake_version "${image}")" || {
    printf '%s\n' "${output}" >&2
    fail "cmake is not runnable in ${image}"
  }

  assert_contains "${output}" "cmake version 3.26.0"
}

assert_cmake_version "tf-particles/devops/cuda-builder:centos7-12.4.0"
assert_cmake_version "tf-particles/devops/cuda-builder:rocky8-12.9.1"
assert_cmake_version "tf-particles/devops/cuda-builder:ubuntu2204-12.9.1"

echo "cmake runtime tests passed"
