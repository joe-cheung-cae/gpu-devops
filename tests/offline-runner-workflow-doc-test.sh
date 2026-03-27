#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

assert_contains() {
  local file="$1"
  local pattern="$2"
  if ! grep -Fq "$pattern" "$file"; then
    echo "Expected to find '$pattern' in $file" >&2
    exit 1
  fi
}

assert_online_offline_workflow() {
  local file="$1"
  assert_contains "$file" "scripts/build-builder-image.sh --all-platforms"
  assert_contains "$file" "scripts/prepare-runner-service-image.sh"
  assert_contains "$file" "scripts/export-images.sh"
  assert_contains "$file" "scripts/import-images.sh"
  assert_contains "$file" "scripts/runner-compose.sh up -d"
  assert_contains "$file" "runner/register-runner.sh gpu"
  assert_contains "$file" "scripts/compose.sh run --rm cuda-cxx-centos7"
}

assert_online_offline_workflow "${ROOT_DIR}/README.md"
assert_online_offline_workflow "${ROOT_DIR}/docs/operations.md"
assert_online_offline_workflow "${ROOT_DIR}/docs/usage.en.md"
assert_online_offline_workflow "${ROOT_DIR}/docs/usage.zh-CN.md"

echo "offline runner workflow docs verified"
