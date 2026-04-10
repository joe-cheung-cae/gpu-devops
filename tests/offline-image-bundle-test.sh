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

assert_not_contains() {
  local file="$1"
  local unexpected="$2"
  if [[ ! -f "${file}" ]]; then
    return 0
  fi
  if grep -Fq -- "${unexpected}" "${file}"; then
    echo "Did not expect to find: ${unexpected}" >&2
    echo "In file: ${file}" >&2
    cat "${file}" >&2 || true
    fail "unexpected content present"
  fi
}

assert_file_exists() {
  local path="$1"
  [[ -f "${path}" ]] || fail "expected file to exist: ${path}"
}

run_export_test() {
  local test_dir="${TMP_DIR}/export"
  mkdir -p "${test_dir}/bin" "${test_dir}/logs"

cat > "${test_dir}/.env" <<'EOF'
BUILDER_CUDA_VERSION=12.9.1
BUILDER_PLATFORM_CUDA_VERSIONS=centos7=12.4.0,rocky8=12.9.1,rocky9=12.9.1,ubuntu2204=12.9.1,ubuntu2404=12.9.1
BUILDER_PLATFORMS=centos7,rocky8,rocky9,ubuntu2204,ubuntu2404
IMAGE_ARCHIVE_PATH=artifacts/offline-images.tar.gz
EOF

  cat > "${test_dir}/bin/docker" <<'EOF'
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
esac
exit 0
EOF
  chmod +x "${test_dir}/bin/docker"

  TEST_LOG_FILE="${test_dir}/logs/docker.log" \
  PATH="${test_dir}/bin:${PATH}" \
  "${ROOT_DIR}/scripts/export/images.sh" --env-file "${test_dir}/.env" --output "${test_dir}/bundle.tar.gz" > "${test_dir}/stdout.log"

  assert_file_exists "${test_dir}/bundle.tar.gz"
  assert_file_exists "${test_dir}/bundle.tar.gz.images.txt"
  assert_file_exists "${test_dir}/bundle.tar.gz.sha256"
assert_contains "${test_dir}/stdout.log" "[1/5] Loading environment"
assert_contains "${test_dir}/stdout.log" "[5/5] Exported image bundle"
assert_contains "${test_dir}/logs/docker.log" "save tf-particles/devops/cuda-builder:centos7-12.4.0 tf-particles/devops/cuda-builder:rocky8-12.9.1 tf-particles/devops/cuda-builder:rocky9-12.9.1 tf-particles/devops/cuda-builder:ubuntu2204-12.9.1 tf-particles/devops/cuda-builder:ubuntu2404-12.9.1"
}

run_export_single_platform_test() {
  local test_dir="${TMP_DIR}/export-single"
  mkdir -p "${test_dir}/bin" "${test_dir}/logs"

cat > "${test_dir}/.env" <<'EOF'
BUILDER_CUDA_VERSION=12.9.1
BUILDER_PLATFORM_CUDA_VERSIONS=centos7=12.4.0,rocky8=12.9.1,rocky9=12.9.1,ubuntu2204=12.9.1,ubuntu2404=12.9.1
BUILDER_PLATFORMS=centos7,rocky8,rocky9,ubuntu2204,ubuntu2404
BUILDER_DEFAULT_PLATFORM=ubuntu2404
IMAGE_ARCHIVE_PATH=artifacts/offline-images.tar.gz
EOF

  cat > "${test_dir}/bin/docker" <<'EOF'
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
esac
exit 0
EOF
  chmod +x "${test_dir}/bin/docker"

  TEST_LOG_FILE="${test_dir}/logs/docker.log" \
  PATH="${test_dir}/bin:${PATH}" \
  "${ROOT_DIR}/scripts/export/images.sh" \
    --env-file "${test_dir}/.env" \
    --output "${test_dir}/bundle.tar.gz" \
    --platform centos7 > "${test_dir}/stdout.log"

  assert_contains "${test_dir}/logs/docker.log" "save tf-particles/devops/cuda-builder:centos7-12.4.0"
  assert_not_contains "${test_dir}/logs/docker.log" "save tf-particles/devops/cuda-builder:rocky8-12.9.1"
  assert_not_contains "${test_dir}/logs/docker.log" "save tf-particles/devops/cuda-builder:rocky9-12.9.1"
  assert_not_contains "${test_dir}/logs/docker.log" "save tf-particles/devops/cuda-builder:ubuntu2204-12.9.1"
  assert_not_contains "${test_dir}/logs/docker.log" "save tf-particles/devops/cuda-builder:ubuntu2404-12.9.1"
  assert_contains "${test_dir}/bundle.tar.gz.images.txt" "tf-particles/devops/cuda-builder:centos7-12.4.0"
}

run_export_rocky9_platform_test() {
  local test_dir="${TMP_DIR}/export-rocky9"
  mkdir -p "${test_dir}/bin" "${test_dir}/logs"

cat > "${test_dir}/.env" <<'EOF'
BUILDER_CUDA_VERSION=12.9.1
BUILDER_PLATFORM_CUDA_VERSIONS=centos7=12.4.0,rocky8=12.9.1,rocky9=12.9.1,ubuntu2204=12.9.1,ubuntu2404=12.9.1
BUILDER_PLATFORMS=centos7,rocky8,rocky9,ubuntu2204,ubuntu2404
BUILDER_DEFAULT_PLATFORM=ubuntu2404
IMAGE_ARCHIVE_PATH=artifacts/offline-images.tar.gz
EOF

  cat > "${test_dir}/bin/docker" <<'EOF'
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
esac
exit 0
EOF
  chmod +x "${test_dir}/bin/docker"

  TEST_LOG_FILE="${test_dir}/logs/docker.log" \
  PATH="${test_dir}/bin:${PATH}" \
  "${ROOT_DIR}/scripts/export/images.sh" \
    --env-file "${test_dir}/.env" \
    --output "${test_dir}/bundle.tar.gz" \
    --platform rocky9 > "${test_dir}/stdout.log"

  assert_contains "${test_dir}/logs/docker.log" "save tf-particles/devops/cuda-builder:rocky9-12.9.1"
  assert_not_contains "${test_dir}/logs/docker.log" "save tf-particles/devops/cuda-builder:centos7-12.4.0"
  assert_not_contains "${test_dir}/logs/docker.log" "save tf-particles/devops/cuda-builder:rocky8-12.9.1"
  assert_not_contains "${test_dir}/logs/docker.log" "save tf-particles/devops/cuda-builder:ubuntu2204-12.9.1"
  assert_not_contains "${test_dir}/logs/docker.log" "save tf-particles/devops/cuda-builder:ubuntu2404-12.9.1"
  assert_contains "${test_dir}/bundle.tar.gz.images.txt" "tf-particles/devops/cuda-builder:rocky9-12.9.1"
}

run_export_ubuntu2404_platform_test() {
  local test_dir="${TMP_DIR}/export-ubuntu2404"
  mkdir -p "${test_dir}/bin" "${test_dir}/logs"

cat > "${test_dir}/.env" <<'EOF'
BUILDER_CUDA_VERSION=12.9.1
BUILDER_PLATFORM_CUDA_VERSIONS=centos7=12.4.0,rocky8=12.9.1,rocky9=12.9.1,ubuntu2204=12.9.1,ubuntu2404=12.9.1
BUILDER_PLATFORMS=centos7,rocky8,rocky9,ubuntu2204,ubuntu2404
BUILDER_DEFAULT_PLATFORM=ubuntu2404
IMAGE_ARCHIVE_PATH=artifacts/offline-images.tar.gz
EOF

  cat > "${test_dir}/bin/docker" <<'EOF'
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
esac
exit 0
EOF
  chmod +x "${test_dir}/bin/docker"

  TEST_LOG_FILE="${test_dir}/logs/docker.log" \
  PATH="${test_dir}/bin:${PATH}" \
  "${ROOT_DIR}/scripts/export/images.sh" \
    --env-file "${test_dir}/.env" \
    --output "${test_dir}/bundle.tar.gz" \
    --platform ubuntu2404 > "${test_dir}/stdout.log"

  assert_contains "${test_dir}/logs/docker.log" "save tf-particles/devops/cuda-builder:ubuntu2404-12.9.1"
  assert_not_contains "${test_dir}/logs/docker.log" "save tf-particles/devops/cuda-builder:centos7-12.4.0"
  assert_not_contains "${test_dir}/logs/docker.log" "save tf-particles/devops/cuda-builder:rocky8-12.9.1"
  assert_not_contains "${test_dir}/logs/docker.log" "save tf-particles/devops/cuda-builder:rocky9-12.9.1"
  assert_not_contains "${test_dir}/logs/docker.log" "save tf-particles/devops/cuda-builder:ubuntu2204-12.9.1"
  assert_contains "${test_dir}/bundle.tar.gz.images.txt" "tf-particles/devops/cuda-builder:ubuntu2404-12.9.1"
}

run_export_cuda_override_test() {
  local test_dir="${TMP_DIR}/export-override"
  mkdir -p "${test_dir}/bin" "${test_dir}/logs"

  cat > "${test_dir}/.env" <<'EOF'
BUILDER_CUDA_VERSION=11.7.1
BUILDER_PLATFORMS=centos7,rocky8,rocky9,ubuntu2204,ubuntu2404
BUILDER_DEFAULT_PLATFORM=ubuntu2404
IMAGE_ARCHIVE_PATH=artifacts/offline-images.tar.gz
EOF

  cat > "${test_dir}/bin/docker" <<'EOF'
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
esac
exit 0
EOF
  chmod +x "${test_dir}/bin/docker"

  TEST_LOG_FILE="${test_dir}/logs/docker.log" \
  PATH="${test_dir}/bin:${PATH}" \
  "${ROOT_DIR}/scripts/export/images.sh" \
    --env-file "${test_dir}/.env" \
    --output "${test_dir}/bundle.tar.gz" \
    --cuda-version 12.4.1 > "${test_dir}/stdout.log"

  assert_contains "${test_dir}/logs/docker.log" "save tf-particles/devops/cuda-builder:centos7-12.4.1 tf-particles/devops/cuda-builder:rocky8-12.4.1 tf-particles/devops/cuda-builder:rocky9-12.4.1 tf-particles/devops/cuda-builder:ubuntu2204-12.4.1 tf-particles/devops/cuda-builder:ubuntu2404-12.4.1"
  assert_contains "${test_dir}/bundle.tar.gz.images.txt" "tf-particles/devops/cuda-builder:ubuntu2404-12.4.1"
}

run_import_test() {
  local test_dir="${TMP_DIR}/import"
  mkdir -p "${test_dir}/bin" "${test_dir}/logs"

  cat > "${test_dir}/.env" <<'EOF'
IMAGE_ARCHIVE_PATH=artifacts/offline-images.tar.gz
EOF

  printf 'fake-image-data' | gzip -c > "${test_dir}/bundle.tar.gz"
  (
    cd "${test_dir}"
    sha256sum bundle.tar.gz > bundle.tar.gz.sha256
  )

  cat > "${test_dir}/bin/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
LOG_FILE="${TEST_LOG_FILE:?}"
printf '%s\n' "$*" >> "${LOG_FILE}"
cat >/dev/null
exit 0
EOF
  chmod +x "${test_dir}/bin/docker"

  TEST_LOG_FILE="${test_dir}/logs/docker.log" \
  PATH="${test_dir}/bin:${PATH}" \
  "${ROOT_DIR}/scripts/import/images.sh" --env-file "${test_dir}/.env" --input "${test_dir}/bundle.tar.gz" > "${test_dir}/stdout.log"

  assert_contains "${test_dir}/logs/docker.log" "load"
  assert_contains "${test_dir}/stdout.log" "[3/4] Loading image archive into Docker"
  assert_contains "${test_dir}/stdout.log" "[4/4] Imported image bundle"
}

run_import_hash_failure_test() {
  local test_dir="${TMP_DIR}/import-hash-failure"
  mkdir -p "${test_dir}/bin" "${test_dir}/logs"

  cat > "${test_dir}/.env" <<'EOF'
IMAGE_ARCHIVE_PATH=artifacts/offline-images.tar.gz
EOF

  printf 'fake-image-data' | gzip -c > "${test_dir}/bundle.tar.gz"
  printf '0000000000000000000000000000000000000000000000000000000000000000  bundle.tar.gz\n' > "${test_dir}/bundle.tar.gz.sha256"

  cat > "${test_dir}/bin/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
LOG_FILE="${TEST_LOG_FILE:?}"
printf '%s\n' "$*" >> "${LOG_FILE}"
cat >/dev/null
exit 0
EOF
  chmod +x "${test_dir}/bin/docker"

  set +e
  TEST_LOG_FILE="${test_dir}/logs/docker.log" \
  PATH="${test_dir}/bin:${PATH}" \
  "${ROOT_DIR}/scripts/import/images.sh" --env-file "${test_dir}/.env" --input "${test_dir}/bundle.tar.gz" >"${test_dir}/stdout.log" 2>"${test_dir}/stderr.log"
  local status=$?
  set -e

  if [[ "${status}" -eq 0 ]]; then
    fail "expected import to fail on hash mismatch"
  fi
  assert_contains "${test_dir}/stderr.log" "SHA256 verification failed"
  assert_not_contains "${test_dir}/logs/docker.log" "load"
}

run_export_test
run_export_single_platform_test
run_export_rocky9_platform_test
run_export_ubuntu2404_platform_test
run_export_cuda_override_test
run_import_test
run_import_hash_failure_test

echo "offline image bundle tests passed"
