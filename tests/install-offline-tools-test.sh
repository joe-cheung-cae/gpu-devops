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

PREFIX="${TMP_DIR}/opt/gpu-devops"
MOCK_BIN="${TMP_DIR}/bin"
mkdir -p "${MOCK_BIN}"

cat > "${MOCK_BIN}/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
LOG_FILE="${TEST_LOG_FILE:?}"
printf '%s\n' "$*" >> "${LOG_FILE}"
case "${1:-}" in
  image)
    shift
    if [[ "${1:-}" == "inspect" ]]; then
      if [[ "${2:-}" == "--format" ]]; then
        printf '123456789\n'
      fi
      exit 0
    fi
    ;;
  save)
    printf 'fake-image-data'
    exit 0
    ;;
  load)
    cat >/dev/null
    exit 0
    ;;
esac
exit 0
EOF
chmod +x "${MOCK_BIN}/docker"

PATH="${MOCK_BIN}:${PATH}" "${ROOT_DIR}/scripts/install-offline-tools.sh" --prefix "${PREFIX}" > "${TMP_DIR}/install.stdout"

assert_file_exists "${PREFIX}/bin/build-builder-image.sh"
assert_file_exists "${PREFIX}/bin/export-images.sh"
assert_file_exists "${PREFIX}/bin/import-images.sh"
assert_file_exists "${PREFIX}/scripts/common/env.sh"
assert_file_exists "${PREFIX}/scripts/common/images.sh"
assert_file_exists "${PREFIX}/scripts/build-builder-image.sh"
assert_file_exists "${PREFIX}/scripts/export/images.sh"
assert_file_exists "${PREFIX}/scripts/import/images.sh"
assert_file_exists "${PREFIX}/docker/cuda-builder/centos7.Dockerfile"
assert_file_exists "${PREFIX}/third_party/cache/cmake-3.26.0-linux-x86_64.tar.gz"
assert_file_exists "${PREFIX}/.env"
assert_file_exists "${PREFIX}/.env.example"
assert_contains "${PREFIX}/.env" 'BUILDER_CUDA_VERSION=11.7.1'

(
  cd "${TMP_DIR}"
  TEST_LOG_FILE="${TMP_DIR}/build.log" PATH="${MOCK_BIN}:${PREFIX}/bin:${PATH}" build-builder-image.sh --platform ubuntu2204 > "${TMP_DIR}/build.stdout"
)
assert_contains "${TMP_DIR}/build.log" "-f ${PREFIX}/docker/cuda-builder/ubuntu2204.Dockerfile"
assert_contains "${TMP_DIR}/build.log" "-t tf-particles/devops/cuda-builder:cuda11.7.1-cmake3.26-ubuntu2204"
assert_contains "${TMP_DIR}/build.log" "--build-arg CUDA_VERSION=11.7.1"

(
  cd "${TMP_DIR}"
  TEST_LOG_FILE="${TMP_DIR}/export.log" PATH="${MOCK_BIN}:${PREFIX}/bin:${PATH}" export-images.sh > "${TMP_DIR}/export.stdout"
)
assert_contains "${TMP_DIR}/export.log" "save tf-particles/devops/cuda-builder:cuda11.7.1-cmake3.26-centos7 tf-particles/devops/cuda-builder:cuda11.7.1-cmake3.26-rocky8 tf-particles/devops/cuda-builder:cuda11.7.1-cmake3.26-ubuntu2204"
assert_file_exists "${PREFIX}/artifacts/offline-images.tar.gz"
assert_file_exists "${PREFIX}/artifacts/offline-images.tar.gz.images.txt"
assert_file_exists "${PREFIX}/artifacts/offline-images.tar.gz.sha256"

(
  cd "${TMP_DIR}"
  TEST_LOG_FILE="${TMP_DIR}/import.log" PATH="${MOCK_BIN}:${PREFIX}/bin:${PATH}" import-images.sh > "${TMP_DIR}/import.stdout"
)
assert_contains "${TMP_DIR}/import.log" "load"
assert_contains "${TMP_DIR}/import.stdout" "[4/4] Imported image bundle"

echo "offline deployment installer test passed"
