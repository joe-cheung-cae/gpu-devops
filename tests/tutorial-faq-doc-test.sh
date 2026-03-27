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

for file in "${ROOT_DIR}/docs/tutorial.zh-CN.md" "${ROOT_DIR}/docs/tutorial.en.md"; do
  assert_contains "$file" "nvidia-container-toolkit"
  assert_contains "$file" "could not select device driver"
  assert_contains "$file" "_apt"
  assert_contains "$file" "nvidia-container-toolkit-ubuntu2004-offline.tar.gz"
  assert_contains "$file" "tar -czf"
  assert_contains "$file" "ubuntu:20.04"
done

echo "tutorial faq docs verified"
