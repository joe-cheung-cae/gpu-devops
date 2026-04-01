#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

# shellcheck disable=SC1091
source "${ROOT_DIR}/scripts/common/third-party-registry.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_eq() {
  local actual="$1"
  local expected="$2"
  if [[ "${actual}" != "${expected}" ]]; then
    fail "expected '${expected}', got '${actual}'"
  fi
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  if [[ "${haystack}" != *"${needle}"* ]]; then
    fail "expected '${haystack}' to contain '${needle}'"
  fi
}

all_deps="$(third_party_all_deps_csv)"
assert_eq "${all_deps}" "chrono,eigen3,openmpi,hdf5,h5engine,muparserx"

resolved_h5engine="$(third_party_resolve_dep_order "h5engine" linux)"
assert_eq "${resolved_h5engine}" "hdf5,h5engine"

resolved_mixed="$(third_party_resolve_dep_order "muparserx,h5engine,chrono" linux)"
assert_eq "${resolved_mixed}" "chrono,hdf5,h5engine,muparserx"

if third_party_validate_dep "unknown" >/dev/null 2>&1; then
  fail "unknown dependency should fail validation"
fi

if third_party_resolve_dep_order "h5engine" windows >/dev/null 2>"${TMP_DIR}/registry-test.err"; then
  fail "windows h5engine resolution should fail"
fi
windows_error="$(cat "${TMP_DIR}/registry-test.err")"
assert_contains "${windows_error}" "does not support host"

assert_eq "$(third_party_windows_install_function openmpi)" "install_windows_msmpi"

echo "third party registry tests passed"
