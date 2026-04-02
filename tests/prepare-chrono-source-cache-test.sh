#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

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
    cat "${file}" >&2 || true
    fail "missing expected content"
  fi
}

SOURCE_REPO="${TMP_DIR}/chrono-upstream"
git init "${SOURCE_REPO}" >/dev/null
(
  cd "${SOURCE_REPO}"
  git config user.name "Test User"
  git config user.email "test@example.com"
  mkdir -p src/chrono
  cat > src/chrono/CMakeLists.txt <<'EOF'
target_link_libraries(ChronoEngine ${OPENMP_LIBRARIES} ${CH_SOCKET_LIB})
EOF
  printf 'chrono source\n' > README.md
  git add README.md src/chrono/CMakeLists.txt
  git commit -m "Initial chrono source" >/dev/null
)

EXPECTED_REF="$(
  cd "${SOURCE_REPO}"
  git rev-parse --short=9 HEAD
)"

CACHE_DIR="${TMP_DIR}/chrono-cache"
ARCHIVE_PATH="${TMP_DIR}/chrono-source.tar.gz"
cmake_archive="${TMP_DIR}/cmake-3.26.0-linux-x86_64.tar.gz"

mkdir -p "${TMP_DIR}/bin"
cat > "${TMP_DIR}/bin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
output=""
while [[ $# -gt 0 ]]; do
  case "${1}" in
    -o)
      output="${2:?Missing output for -o}"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
mkdir -p "$(dirname "${output}")"
printf 'placeholder cmake archive\n' > "${output}"
EOF
chmod +x "${TMP_DIR}/bin/curl"

CHRONO_GIT_URL="${SOURCE_REPO}" \
CHRONO_GIT_REF="${EXPECTED_REF}" \
CHRONO_CACHE_DIR="${CACHE_DIR}" \
CHRONO_ARCHIVE_OUTPUT="${ARCHIVE_PATH}" \
CMAKE_ARCHIVE_OUTPUT="${cmake_archive}" \
PATH="${TMP_DIR}/bin:${PATH}" \
  "${ROOT_DIR}/scripts/prepare-third-party-cache.sh" --deps chrono > "${TMP_DIR}/stdout.log"

assert_file_exists "${ARCHIVE_PATH}"
assert_contains "${TMP_DIR}/stdout.log" "Prepared third-party archives"
assert_file_exists "${cmake_archive}"

if tar -tzf "${ARCHIVE_PATH}" | grep -q '^.git'; then
  fail "archive should not contain .git metadata"
fi

if ! tar -tzf "${ARCHIVE_PATH}" | grep -q 'README.md$'; then
  fail "archive should contain tracked source files"
fi

if ! tar -tzf "${ARCHIVE_PATH}" | grep -q '\.chrono-source-ref$'; then
  fail "archive should contain .chrono-source-ref"
fi

if ! gzip -dc "${ARCHIVE_PATH}" | tar -xO "./.chrono-source-ref" 2>/dev/null | grep -Fxq "${EXPECTED_REF}"; then
  fail "archive should contain .chrono-source-ref with the requested ref"
fi

echo "prepare chrono source cache tests passed"
