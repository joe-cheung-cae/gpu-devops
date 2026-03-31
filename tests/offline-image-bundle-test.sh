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
  "${ROOT_DIR}/scripts/export-images.sh" --env-file "${test_dir}/.env" --output "${test_dir}/bundle.tar.gz" > "${test_dir}/stdout.log"

  assert_file_exists "${test_dir}/bundle.tar.gz"
  assert_file_exists "${test_dir}/bundle.tar.gz.images.txt"
  assert_file_exists "${test_dir}/bundle.tar.gz.sha256"
  assert_contains "${test_dir}/stdout.log" "[1/5] Loading environment"
  assert_contains "${test_dir}/stdout.log" "[5/5] Exported image bundle"
  assert_contains "${test_dir}/stdout.log" "Starting [1/4] Preparing export for image registry.local/devops/cuda-builder:cuda11.7-cmake3.26-centos7"
  assert_contains "${test_dir}/stdout.log" "image size: 123456789 bytes"
  assert_contains "${test_dir}/stdout.log" "Finished [4/4] Preparing export for image registry.local/devops/gitlab-runner:alpine-v16.10.1"
  assert_contains "${test_dir}/stdout.log" "Starting archive export at"
  assert_contains "${test_dir}/stdout.log" "Finished archive export at"
  assert_contains "${test_dir}/stdout.log" "Archive export elapsed:"
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

run_export_only_runner_service_test() {
  local test_dir="${TMP_DIR}/export-only-runner-service"
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
  "${ROOT_DIR}/scripts/export-images.sh" \
    --env-file "${test_dir}/.env" \
    --output "${test_dir}/bundle.tar.gz" \
    --only-runner-service > "${test_dir}/stdout.log"

  assert_contains "${test_dir}/logs/docker.log" "save registry.local/devops/gitlab-runner:alpine-v16.10.1"
  assert_not_contains "${test_dir}/logs/docker.log" "save registry.local/devops/cuda-builder:cuda11.7-cmake3.26-centos7"
  assert_equals "1" "$(wc -l < "${test_dir}/bundle.tar.gz.images.txt" | tr -d ' ')"
  assert_contains "${test_dir}/bundle.tar.gz.images.txt" "registry.local/devops/gitlab-runner:alpine-v16.10.1"
}

run_export_only_build_images_test() {
  local test_dir="${TMP_DIR}/export-only-build-images"
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
  "${ROOT_DIR}/scripts/export-images.sh" \
    --env-file "${test_dir}/.env" \
    --output "${test_dir}/bundle.tar.gz" \
    --only-build-images > "${test_dir}/stdout.log"

  assert_contains "${test_dir}/logs/docker.log" "save registry.local/devops/cuda-builder:cuda11.7-cmake3.26-centos7 registry.local/devops/cuda-builder:cuda11.7-cmake3.26-rocky8 registry.local/devops/cuda-builder:cuda11.7-cmake3.26-ubuntu2204"
  assert_not_contains "${test_dir}/logs/docker.log" "save registry.local/devops/gitlab-runner:alpine-v16.10.1"
  assert_equals "3" "$(wc -l < "${test_dir}/bundle.tar.gz.images.txt" | tr -d ' ')"
  assert_not_contains "${test_dir}/bundle.tar.gz.images.txt" "registry.local/devops/gitlab-runner:alpine-v16.10.1"
}

run_export_only_build_images_single_platform_test() {
  local test_dir="${TMP_DIR}/export-only-build-images-single-platform"
  mkdir -p "${test_dir}/bin" "${test_dir}/logs"

  cat > "${test_dir}/.env" <<'EOF'
BUILDER_IMAGE_FAMILY=registry.local/devops/cuda-builder:cuda11.7-cmake3.26
BUILDER_PLATFORMS=centos7,rocky8,ubuntu2204
BUILDER_DEFAULT_PLATFORM=centos7
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
  "${ROOT_DIR}/scripts/export-images.sh" \
    --env-file "${test_dir}/.env" \
    --output "${test_dir}/bundle.tar.gz" \
    --only-build-images \
    --platform centos7 > "${test_dir}/stdout.log"

  assert_contains "${test_dir}/logs/docker.log" "save registry.local/devops/cuda-builder:cuda11.7-cmake3.26-centos7"
  assert_not_contains "${test_dir}/logs/docker.log" "save registry.local/devops/cuda-builder:cuda11.7-cmake3.26-rocky8"
  assert_not_contains "${test_dir}/logs/docker.log" "save registry.local/devops/cuda-builder:cuda11.7-cmake3.26-ubuntu2204"
  assert_not_contains "${test_dir}/logs/docker.log" "save registry.local/devops/gitlab-runner:alpine-v16.10.1"
  assert_equals "1" "$(wc -l < "${test_dir}/bundle.tar.gz.images.txt" | tr -d ' ')"
  assert_contains "${test_dir}/bundle.tar.gz.images.txt" "registry.local/devops/cuda-builder:cuda11.7-cmake3.26-centos7"
  assert_not_contains "${test_dir}/bundle.tar.gz.images.txt" "registry.local/devops/cuda-builder:cuda11.7-cmake3.26-rocky8"
  assert_not_contains "${test_dir}/bundle.tar.gz.images.txt" "registry.local/devops/cuda-builder:cuda11.7-cmake3.26-ubuntu2204"
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
  "${ROOT_DIR}/scripts/import-images.sh" --env-file "${test_dir}/.env" --input "${test_dir}/bundle.tar.gz" > "${test_dir}/stdout.log"

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
  "${ROOT_DIR}/scripts/export-project-bundle.sh" --env-file "${test_dir}/.env" --output "${test_dir}/bundle.tar.gz" --mode images > "${test_dir}/export.stdout.log"

  TEST_LOG_FILE="${test_dir}/logs/import.log" \
  PATH="${test_dir}/bin:${PATH}" \
  "${ROOT_DIR}/scripts/import-project-bundle.sh" --env-file "${test_dir}/.env" --input "${test_dir}/bundle.tar.gz" --mode images > "${test_dir}/import.stdout.log"

  assert_contains "${test_dir}/logs/export.log" "save registry.local/devops/cuda-builder:cuda11.7-cmake3.26-centos7 registry.local/devops/gitlab-runner:alpine-v16.10.1"
  assert_file_exists "${test_dir}/bundle.tar.gz.sha256"
  assert_contains "${test_dir}/logs/import.log" "load"
  assert_contains "${test_dir}/export.stdout.log" "[4/5] Creating portable bundle archive"
  assert_contains "${test_dir}/import.stdout.log" "[3/5] Importing bundled images"
}

run_export_test
run_export_only_runner_service_test
run_export_only_build_images_test
run_export_only_build_images_single_platform_test
run_import_test
run_import_hash_failure_test
run_common_helper_regression_test

echo "offline image bundle tests passed"
