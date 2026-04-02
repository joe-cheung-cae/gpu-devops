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

assert_file_exists() {
  local path="$1"
  [[ -f "${path}" ]] || fail "expected file to exist: ${path}"
}

create_git_repo() {
  local repo_path="$1"
  local marker_file="$2"
  git init "${repo_path}" >/dev/null
  (
    cd "${repo_path}"
    git config user.name "Test User"
    git config user.email "test@example.com"
    printf '%s\n' "${marker_file}" > README.md
    git add README.md
    git commit -m "Initial commit" >/dev/null
  )
}

MOCK_BIN="${TMP_DIR}/bin"
mkdir -p "${MOCK_BIN}"
cat > "${MOCK_BIN}/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
output=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o)
      output="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
stage_dir="$(mktemp -d)"
trap 'rm -rf "${stage_dir}"' EXIT
printf 'archive payload\n' > "${stage_dir}/README.txt"
tar -czf "${output}" -C "${stage_dir}" .
EOF
chmod +x "${MOCK_BIN}/curl"

CHRONO_REPO="${TMP_DIR}/chrono-upstream"
MUPARSERX_REPO="${TMP_DIR}/muparserx-upstream"
create_git_repo "${CHRONO_REPO}" "chrono"
create_git_repo "${MUPARSERX_REPO}" "muparserx"

CHRONO_REF="$(
  cd "${CHRONO_REPO}"
  git rev-parse --short=9 HEAD
)"
MUPARSERX_BRANCH="$(
  cd "${MUPARSERX_REPO}"
  git branch --show-current
)"

CHRONO_ARCHIVE="${TMP_DIR}/chrono-source.tar.gz"
EIGEN_ARCHIVE="${TMP_DIR}/eigen-3.4.0.tar.gz"
OPENMPI_ARCHIVE="${TMP_DIR}/openmpi-4.1.6.tar.gz"
MUPARSERX_ARCHIVE="${TMP_DIR}/muparserx-source.tar.gz"
CMAKE_ARCHIVE="${TMP_DIR}/cmake-3.26.0-linux-x86_64.tar.gz"

PATH="${MOCK_BIN}:${PATH}" \
CHRONO_GIT_URL="${CHRONO_REPO}" \
CHRONO_GIT_REF="${CHRONO_REF}" \
CHRONO_CACHE_DIR="${TMP_DIR}/chrono-cache" \
CHRONO_ARCHIVE_OUTPUT="${CHRONO_ARCHIVE}" \
MUPARSERX_GIT_URL="${MUPARSERX_REPO}" \
MUPARSERX_GIT_BRANCH="${MUPARSERX_BRANCH}" \
MUPARSERX_CACHE_DIR="${TMP_DIR}/muparserx-cache" \
MUPARSERX_ARCHIVE_OUTPUT="${MUPARSERX_ARCHIVE}" \
EIGEN3_ARCHIVE_OUTPUT="${EIGEN_ARCHIVE}" \
OPENMPI_ARCHIVE_OUTPUT="${OPENMPI_ARCHIVE}" \
CMAKE_ARCHIVE_OUTPUT="${CMAKE_ARCHIVE}" \
  "${ROOT_DIR}/scripts/prepare-third-party-cache.sh" --deps chrono,eigen3,openmpi,muparserx > "${TMP_DIR}/stdout.log"

assert_file_exists "${CHRONO_ARCHIVE}"
assert_file_exists "${EIGEN_ARCHIVE}"
assert_file_exists "${OPENMPI_ARCHIVE}"
assert_file_exists "${MUPARSERX_ARCHIVE}"
assert_file_exists "${CMAKE_ARCHIVE}"

if ! tar -tzf "${CHRONO_ARCHIVE}" | grep -q '\.chrono-source-ref$'; then
  fail "chrono archive should contain .chrono-source-ref"
fi

if ! tar -tzf "${MUPARSERX_ARCHIVE}" | grep -q '\.muparserx-source-ref$'; then
  fail "muparserx archive should contain .muparserx-source-ref"
fi

PATH="${MOCK_BIN}:${PATH}" \
HDF5_ARCHIVE_OUTPUT="${TMP_DIR}/missing-hdf5.tar.gz" \
H5ENGINE_SPH_ARCHIVE_OUTPUT="${TMP_DIR}/missing-h5engine-sph.tar.gz" \
H5ENGINE_DEM_ARCHIVE_OUTPUT="${TMP_DIR}/missing-h5engine-dem.tar.gz" \
  "${ROOT_DIR}/scripts/prepare-third-party-cache.sh" --deps h5engine > "${TMP_DIR}/h5engine.stdout"
assert_file_exists "${TMP_DIR}/missing-hdf5.tar.gz"
assert_file_exists "${TMP_DIR}/missing-h5engine-sph.tar.gz"
assert_file_exists "${TMP_DIR}/missing-h5engine-dem.tar.gz"

assert_file_exists "${ROOT_DIR}/scripts/common/third-party-registry.sh"

REGISTRY_STDOUT="${TMP_DIR}/registry.stdout"
python3 - "${ROOT_DIR}/scripts/common/third-party-registry.sh" > /dev/null <<'PY'
PY
bash -lc "source '${ROOT_DIR}/scripts/common/third-party-registry.sh'; third_party_all_deps_csv" > "${REGISTRY_STDOUT}"
assert_contains "${REGISTRY_STDOUT}" "chrono,eigen3,openmpi,hdf5,h5engine,muparserx"

RESOLVE_STDOUT="${TMP_DIR}/resolve.stdout"
bash -lc "source '${ROOT_DIR}/scripts/common/third-party-registry.sh'; third_party_resolve_dep_order 'h5engine' linux" > "${RESOLVE_STDOUT}"
assert_contains "${RESOLVE_STDOUT}" "hdf5,h5engine"

WINDOWS_RESOLVE_STDOUT="${TMP_DIR}/resolve-windows.stdout"
bash -lc "source '${ROOT_DIR}/scripts/common/third-party-registry.sh'; third_party_resolve_dep_order 'openmpi' windows" > "${WINDOWS_RESOLVE_STDOUT}"
assert_contains "${WINDOWS_RESOLVE_STDOUT}" "openmpi"

echo "prepare third-party cache tests passed"
