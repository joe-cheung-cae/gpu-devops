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

assert_equals() {
  local expected="$1"
  local actual="$2"
  if [[ "${expected}" != "${actual}" ]]; then
    fail "expected '${expected}', got '${actual}'"
  fi
}

TOOLKIT_ROOT="${TMP_DIR}/toolkit"
mkdir -p "${TOOLKIT_ROOT}/scripts/common"

cat > "${TOOLKIT_ROOT}/scripts/common/third-party-registry.sh" <<'EOF'
third_party_all_deps_csv() {
  printf '%s\n' 'chrono,eigen3,openmpi,hdf5,h5engine,muparserx'
}

third_party_validate_dep() {
  case "$1" in
    chrono|eigen3|openmpi|hdf5|h5engine|muparserx) ;;
    *) return 1 ;;
  esac
}

third_party_dep_direct_deps() {
  case "$1" in
    h5engine)
      printf '%s\n' 'hdf5'
      ;;
    *)
      printf '\n'
      ;;
  esac
}

third_party_resolve_dep_order() {
  local deps_csv="$1"
  local host="$2"
  local dep
  local requested=()
  local ordered=()

  IFS=',' read -r -a requested <<< "${deps_csv}"
  for dep in "${requested[@]}"; do
    dep="${dep//[[:space:]]/}"
    [[ -n "${dep}" ]] || continue
    case "${dep}" in
      h5engine)
        requested+=(hdf5)
        ;;
    esac
  done

  for dep in chrono eigen3 openmpi hdf5 h5engine muparserx; do
    for candidate in "${requested[@]}"; do
      if [[ "${candidate}" == "${dep}" ]]; then
        ordered+=("${dep}")
        break
      fi
    done
  done

  (IFS=,; printf '%s\n' "${ordered[*]}")
}

third_party_linux_install_command() {
  local dep="$1"
  local deps_root="$2"
  local cache_root="$3"
  local toolkit_root="${4:-/toolkit}"

  case "${dep}" in
    chrono)
      printf 'printf "chrono\\n" >> "${TEST_LOG_FILE}"\n'
      ;;
    eigen3)
      printf 'printf "eigen3\\n" >> "${TEST_LOG_FILE}"\n'
      ;;
    openmpi)
      printf 'printf "openmpi\\n" >> "${TEST_LOG_FILE}"\n'
      ;;
    hdf5)
      printf 'printf "hdf5\\n" >> "${TEST_LOG_FILE}"\n'
      ;;
    h5engine)
      printf 'printf "h5engine\\n" >> "${TEST_LOG_FILE}"\n'
      ;;
    muparserx)
      printf 'printf "muparserx\\n" >> "${TEST_LOG_FILE}"\n'
      ;;
  esac
}
EOF

LOG_FILE="${TMP_DIR}/order.log"
STDOUT_FILE="${TMP_DIR}/stdout.log"

TEST_LOG_FILE="${LOG_FILE}" TOOLKIT_ROOT="${TOOLKIT_ROOT}" \
  "${ROOT_DIR}/third_party/install-third-party.sh" --deps muparserx,h5engine,chrono > "${STDOUT_FILE}"

assert_equals $'chrono\nhdf5\nh5engine\nmuparserx' "$(cat "${LOG_FILE}")"

SUBSET_LOG_FILE="${TMP_DIR}/subset.log"
TEST_LOG_FILE="${SUBSET_LOG_FILE}" TOOLKIT_ROOT="${TOOLKIT_ROOT}" \
  "${ROOT_DIR}/third_party/install-third-party.sh" --deps chrono,openmpi > "${TMP_DIR}/subset.stdout"
assert_equals $'chrono\nopenmpi' "$(cat "${SUBSET_LOG_FILE}")"

echo "install third-party tests passed"
