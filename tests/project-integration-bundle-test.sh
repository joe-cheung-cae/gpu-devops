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

assert_executable() {
  local path="$1"
  [[ -x "${path}" ]] || fail "expected file to be executable: ${path}"
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
esac
exit 0
EOF
  chmod +x "${test_dir}/bin/docker"

  TEST_LOG_FILE="${test_dir}/logs/docker.log" \
  PATH="${test_dir}/bin:${PATH}" \
  "${ROOT_DIR}/scripts/export-project-bundle.sh" --env-file "${test_dir}/.env" --output "${test_dir}/bundle.tar.gz"

  assert_file_exists "${test_dir}/bundle.tar.gz"
  tar -xzf "${test_dir}/bundle.tar.gz" -C "${test_dir}"
  assert_file_exists "${test_dir}/assets/.env.example"
  assert_file_exists "${test_dir}/assets/docker-compose.yml"
  assert_file_exists "${test_dir}/assets/runner-compose.yml"
  assert_file_exists "${test_dir}/assets/examples/gitlab-ci/shared-gpu-runner.yml"
  assert_file_exists "${test_dir}/assets/scripts/compose.sh"
  assert_file_exists "${test_dir}/images/offline-images.tar.gz"
  assert_file_exists "${test_dir}/images/offline-images.tar.gz.images.txt"
  assert_contains "${test_dir}/logs/docker.log" "save registry.local/devops/cuda-builder:cuda11.7-cmake3.26-centos7 registry.local/devops/cuda-builder:cuda11.7-cmake3.26-rocky8 registry.local/devops/cuda-builder:cuda11.7-cmake3.26-ubuntu2204 registry.local/devops/gitlab-runner:alpine-v16.10.1"
}

run_import_test() {
  local test_dir="${TMP_DIR}/import"
  local target_dir="${TMP_DIR}/external-project"
  mkdir -p "${test_dir}/bin" "${test_dir}/logs"

  cat > "${test_dir}/.env" <<'EOF'
PROJECT_BUNDLE_PATH=artifacts/project-integration-bundle.tar.gz
EOF

  mkdir -p "${test_dir}/bundle/images" "${test_dir}/bundle/assets/examples/gitlab-ci" "${test_dir}/bundle/assets/scripts"
  printf 'fake-image-data' | gzip -c > "${test_dir}/bundle/images/offline-images.tar.gz"
  cp "${ROOT_DIR}/docker-compose.yml" "${test_dir}/bundle/assets/docker-compose.yml"
  cp "${ROOT_DIR}/examples/gitlab-ci/shared-gpu-runner.yml" "${test_dir}/bundle/assets/examples/gitlab-ci/shared-gpu-runner.yml"
  cp "${ROOT_DIR}/scripts/compose.sh" "${test_dir}/bundle/assets/scripts/compose.sh"
  chmod +x "${test_dir}/bundle/assets/scripts/compose.sh"
  tar -czf "${test_dir}/bundle.tar.gz" -C "${test_dir}/bundle" .

  cat > "${test_dir}/bin/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
LOG_FILE="${TEST_LOG_FILE:?}"
printf '%s\n' "$*" >> "${LOG_FILE}"
if [[ "${1:-}" == "compose" ]]; then
  exit 0
fi
cat >/dev/null
exit 0
EOF
  cat > "${test_dir}/bin/docker-compose" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
  chmod +x "${test_dir}/bin/docker"
  chmod +x "${test_dir}/bin/docker-compose"

  TEST_LOG_FILE="${test_dir}/logs/docker.log" \
  PATH="${test_dir}/bin:${PATH}" \
  "${ROOT_DIR}/scripts/import-project-bundle.sh" \
    --env-file "${test_dir}/.env" \
    --input "${test_dir}/bundle.tar.gz" \
    --target-dir "${target_dir}"

  assert_contains "${test_dir}/logs/docker.log" "load"
  assert_file_exists "${target_dir}/.gpu-devops/docker-compose.yml"
  assert_file_exists "${target_dir}/.gpu-devops/examples/gitlab-ci/shared-gpu-runner.yml"
  assert_file_exists "${target_dir}/.gpu-devops/scripts/compose.sh"
  assert_file_exists "${target_dir}/.gpu-devops/.env"
  assert_executable "${target_dir}/.gpu-devops/scripts/compose.sh"
  assert_contains "${target_dir}/.gpu-devops/.env" "HOST_PROJECT_DIR=${target_dir}"
  assert_contains "${target_dir}/.gpu-devops/.env" "CUDA_CXX_PROJECT_DIR=."
  assert_contains "${target_dir}/.gpu-devops/.env" "CUDA_CXX_BUILD_ROOT=.gpu-devops/artifacts/cuda-cxx-build"

  TEST_LOG_FILE="${test_dir}/logs/docker.log" \
  PATH="${test_dir}/bin:${PATH}" \
  "${target_dir}/.gpu-devops/scripts/compose.sh" config

  assert_contains "${test_dir}/logs/docker.log" "compose --env-file ${target_dir}/.gpu-devops/.env -f ${target_dir}/.gpu-devops/docker-compose.yml config"
}

run_export_test
run_import_test

echo "project integration bundle tests passed"
