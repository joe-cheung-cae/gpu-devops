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

assert_equals() {
  local expected="$1"
  local actual="$2"
  if [[ "${expected}" != "${actual}" ]]; then
    fail "expected '${expected}', got '${actual}'"
  fi
}

run_export_test() {
  local test_dir="${TMP_DIR}/export"
  mkdir -p "${test_dir}/bin" "${test_dir}/logs"

  cat > "${test_dir}/.env" <<'EOF'
BUILDER_IMAGE_FAMILY=registry.local/devops/cuda-builder:cuda11.7-cmake3.26
BUILDER_PLATFORMS=centos7,rocky8,ubuntu2204
BUILDER_IMAGE=registry.local/devops/cuda-builder:cuda11.7-cmake3.26-centos7
RUNNER_DOCKER_IMAGE=registry.local/devops/cuda-builder:cuda11.7-cmake3.26-centos7
RUNNER_SERVICE_IMAGE=registry.local/devops/gitlab-runner:alpine-v16.10.1
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
  "${ROOT_DIR}/scripts/export-images.sh" --env-file "${test_dir}/.env" --output "${test_dir}/bundle.tar.gz"

  assert_file_exists "${test_dir}/bundle.tar.gz"
  assert_file_exists "${test_dir}/bundle.tar.gz.images.txt"
  assert_file_exists "${test_dir}/bundle.tar.gz.sha256"
  assert_contains "${test_dir}/logs/docker.log" "image inspect registry.local/devops/cuda-builder:cuda11.7-cmake3.26-centos7"
  assert_contains "${test_dir}/logs/docker.log" "image inspect registry.local/devops/cuda-builder:cuda11.7-cmake3.26-rocky8"
  assert_contains "${test_dir}/logs/docker.log" "image inspect registry.local/devops/cuda-builder:cuda11.7-cmake3.26-ubuntu2204"
  assert_contains "${test_dir}/logs/docker.log" "image inspect registry.local/devops/gitlab-runner:alpine-v16.10.1"
  assert_contains "${test_dir}/logs/docker.log" "save registry.local/devops/cuda-builder:cuda11.7-cmake3.26-centos7 registry.local/devops/cuda-builder:cuda11.7-cmake3.26-rocky8 registry.local/devops/cuda-builder:cuda11.7-cmake3.26-ubuntu2204 registry.local/devops/gitlab-runner:alpine-v16.10.1"
  assert_contains "${test_dir}/bundle.tar.gz.images.txt" "registry.local/devops/cuda-builder:cuda11.7-cmake3.26-centos7"
  assert_contains "${test_dir}/bundle.tar.gz.images.txt" "registry.local/devops/cuda-builder:cuda11.7-cmake3.26-rocky8"
  assert_contains "${test_dir}/bundle.tar.gz.images.txt" "registry.local/devops/cuda-builder:cuda11.7-cmake3.26-ubuntu2204"
  assert_contains "${test_dir}/bundle.tar.gz.images.txt" "registry.local/devops/gitlab-runner:alpine-v16.10.1"
  assert_contains "${test_dir}/bundle.tar.gz.sha256" "bundle.tar.gz"
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
  "${ROOT_DIR}/scripts/import-images.sh" --env-file "${test_dir}/.env" --input "${test_dir}/bundle.tar.gz"

  assert_contains "${test_dir}/logs/docker.log" "load"
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
  "${ROOT_DIR}/scripts/import-images.sh" --env-file "${test_dir}/.env" --input "${test_dir}/bundle.tar.gz" >"${test_dir}/stdout.log" 2>"${test_dir}/stderr.log"
  local status=$?
  set -e

  assert_equals "1" "${status}"
  assert_contains "${test_dir}/stderr.log" "SHA256 verification failed"
  assert_not_contains "${test_dir}/logs/docker.log" "load"
}

run_common_helper_regression_test() {
  local test_dir="${TMP_DIR}/helper-regression"
  mkdir -p "${test_dir}/bin" "${test_dir}/logs"

  cat > "${test_dir}/.env" <<'EOF'
BUILDER_IMAGE_FAMILY=registry.local/devops/cuda-builder:cuda11.7-cmake3.26
BUILDER_PLATFORMS=centos7
BUILDER_IMAGE=registry.local/devops/cuda-builder:cuda11.7-cmake3.26-centos7
RUNNER_DOCKER_IMAGE=registry.local/devops/cuda-builder:cuda11.7-cmake3.26-centos7
RUNNER_SERVICE_IMAGE=registry.local/devops/gitlab-runner:alpine-v16.10.1
PROJECT_BUNDLE_PATH=artifacts/project-integration-bundle.tar.gz
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
  chmod +x "${test_dir}/bin/docker"

  TEST_LOG_FILE="${test_dir}/logs/export.log" \
  PATH="${test_dir}/bin:${PATH}" \
  "${ROOT_DIR}/scripts/export-project-bundle.sh" --env-file "${test_dir}/.env" --output "${test_dir}/bundle.tar.gz" --mode images

  TEST_LOG_FILE="${test_dir}/logs/import.log" \
  PATH="${test_dir}/bin:${PATH}" \
  "${ROOT_DIR}/scripts/import-project-bundle.sh" --env-file "${test_dir}/.env" --input "${test_dir}/bundle.tar.gz" --mode images

  assert_contains "${test_dir}/logs/export.log" "save registry.local/devops/cuda-builder:cuda11.7-cmake3.26-centos7 registry.local/devops/gitlab-runner:alpine-v16.10.1"
  assert_file_exists "${test_dir}/bundle.tar.gz.sha256"
  assert_contains "${test_dir}/logs/import.log" "load"
}

run_export_test
run_import_test
run_import_hash_failure_test
run_common_helper_regression_test

echo "offline image bundle tests passed"
