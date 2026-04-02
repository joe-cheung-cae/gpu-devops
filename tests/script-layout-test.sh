#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_file_exists() {
  local path="$1"
  [[ -f "${path}" ]] || fail "expected file to exist: ${path}"
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

assert_not_contains() {
  local file="$1"
  local unexpected="$2"
  if grep -Fq -- "${unexpected}" "${file}"; then
    echo "Did not expect to find: ${unexpected}" >&2
    echo "In file: ${file}" >&2
    fail "unexpected content present"
  fi
}

assert_file_exists "${ROOT_DIR}/scripts/export/images.sh"
assert_file_exists "${ROOT_DIR}/scripts/export/project-bundle.sh"
assert_file_exists "${ROOT_DIR}/scripts/import/images.sh"
assert_file_exists "${ROOT_DIR}/scripts/import/project-bundle.sh"
assert_file_exists "${ROOT_DIR}/scripts/common/env.sh"
assert_file_exists "${ROOT_DIR}/scripts/common/images.sh"
assert_file_exists "${ROOT_DIR}/scripts/common/archive.sh"
assert_file_exists "${ROOT_DIR}/scripts/common/project-bundle.sh"
assert_file_exists "${ROOT_DIR}/scripts/common/progress.sh"
assert_file_exists "${ROOT_DIR}/scripts/common/third-party-registry.sh"
assert_file_exists "${ROOT_DIR}/scripts/prepare-third-party-cache.sh"
assert_file_exists "${ROOT_DIR}/scripts/prepare-offline-project-sandbox.sh"
assert_file_exists "${ROOT_DIR}/scripts/install-third-party.sh"
assert_contains "${ROOT_DIR}/scripts/export/images.sh" 'source "${ROOT_DIR}/scripts/common/env.sh"'
assert_contains "${ROOT_DIR}/scripts/export/images.sh" 'source "${ROOT_DIR}/scripts/common/images.sh"'
assert_contains "${ROOT_DIR}/scripts/export/images.sh" 'source "${ROOT_DIR}/scripts/common/archive.sh"'
assert_contains "${ROOT_DIR}/scripts/export/images.sh" 'source "${ROOT_DIR}/scripts/common/progress.sh"'
assert_contains "${ROOT_DIR}/scripts/import/images.sh" 'source "${ROOT_DIR}/scripts/common/env.sh"'
assert_contains "${ROOT_DIR}/scripts/import/images.sh" 'source "${ROOT_DIR}/scripts/common/archive.sh"'
assert_contains "${ROOT_DIR}/scripts/import/images.sh" 'source "${ROOT_DIR}/scripts/common/progress.sh"'
assert_contains "${ROOT_DIR}/scripts/export/project-bundle.sh" 'source "${ROOT_DIR}/scripts/common/env.sh"'
assert_contains "${ROOT_DIR}/scripts/export/project-bundle.sh" 'source "${ROOT_DIR}/scripts/common/images.sh"'
assert_contains "${ROOT_DIR}/scripts/export/project-bundle.sh" 'source "${ROOT_DIR}/scripts/common/third-party-registry.sh"'
assert_contains "${ROOT_DIR}/scripts/export/project-bundle.sh" 'source "${ROOT_DIR}/scripts/common/archive.sh"'
assert_contains "${ROOT_DIR}/scripts/export/project-bundle.sh" 'source "${ROOT_DIR}/scripts/common/project-bundle.sh"'
assert_contains "${ROOT_DIR}/scripts/export/project-bundle.sh" 'source "${ROOT_DIR}/scripts/common/progress.sh"'
assert_contains "${ROOT_DIR}/scripts/import/project-bundle.sh" 'source "${ROOT_DIR}/scripts/common/env.sh"'
assert_contains "${ROOT_DIR}/scripts/import/project-bundle.sh" 'source "${ROOT_DIR}/scripts/common/archive.sh"'
assert_contains "${ROOT_DIR}/scripts/import/project-bundle.sh" 'source "${ROOT_DIR}/scripts/common/project-bundle.sh"'
assert_contains "${ROOT_DIR}/scripts/import/project-bundle.sh" 'source "${ROOT_DIR}/scripts/common/progress.sh"'

for pattern in \
  "git submodule add" \
  "git submodule update" \
  "git submodule sync" \
  "submodule foreach"
do
  if rg -n --fixed-strings --glob '!docs/plans/*' --glob '!tests/script-layout-test.sh' "${pattern}" "${ROOT_DIR}" >/dev/null; then
    fail "submodule write/update command should not appear: ${pattern}"
  fi
done

echo "script layout tests passed"
