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

assert_executable() {
  local path="$1"
  [[ -x "${path}" ]] || fail "expected file to be executable: ${path}"
}

assert_not_exists() {
  local path="$1"
  [[ ! -e "${path}" ]] || fail "expected path to be absent: ${path}"
}

assert_equals() {
  local expected="$1"
  local actual="$2"
  if [[ "${expected}" != "${actual}" ]]; then
    fail "expected '${expected}', got '${actual}'"
  fi
}

write_export_env() {
  local env_path="$1"

  cat > "${env_path}" <<'EOF'
BUILDER_IMAGE_FAMILY=registry.local/devops/cuda-builder:cuda11.7-cmake3.26
BUILDER_PLATFORMS=centos7,rocky8,ubuntu2204
BUILDER_IMAGE=registry.local/devops/cuda-builder:cuda11.7-cmake3.26-centos7
RUNNER_DOCKER_IMAGE=registry.local/devops/cuda-builder:cuda11.7-cmake3.26-centos7
RUNNER_SERVICE_IMAGE=registry.local/devops/gitlab-runner:alpine-v16.10.1
PROJECT_BUNDLE_PATH=artifacts/project-integration-bundle.tar.gz
EOF
}

write_export_docker_mock() {
  local docker_path="$1"

  cat > "${docker_path}" <<'EOF'
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
  chmod +x "${docker_path}"
}

run_export_test() {
  local mode="$1"
  local test_dir="${TMP_DIR}/export-${mode}"
  mkdir -p "${test_dir}/bin" "${test_dir}/logs"

  write_export_env "${test_dir}/.env"
  write_export_docker_mock "${test_dir}/bin/docker"

  TEST_LOG_FILE="${test_dir}/logs/docker.log" \
  PATH="${test_dir}/bin:${PATH}" \
  "${ROOT_DIR}/scripts/export-project-bundle.sh" --env-file "${test_dir}/.env" --output "${test_dir}/bundle.tar.gz" --mode "${mode}" > "${test_dir}/stdout.log"

  assert_file_exists "${test_dir}/bundle.tar.gz"
  assert_file_exists "${test_dir}/bundle.tar.gz.sha256"
  tar -xzf "${test_dir}/bundle.tar.gz" -C "${test_dir}"

  case "${mode}" in
    all)
      assert_file_exists "${test_dir}/assets/.env.example"
      assert_file_exists "${test_dir}/assets/docker-compose.yml"
      assert_file_exists "${test_dir}/assets/runner-compose.yml"
      assert_file_exists "${test_dir}/assets/examples/gitlab-ci/shared-gpu-runner.yml"
      assert_file_exists "${test_dir}/assets/examples/gitlab-ci/shared-gpu-shell-runner.yml"
      assert_file_exists "${test_dir}/assets/scripts/compose.sh"
      assert_file_exists "${test_dir}/assets/scripts/common/env.sh"
      assert_file_exists "${test_dir}/assets/scripts/export/images.sh"
      assert_file_exists "${test_dir}/assets/scripts/import/project-bundle.sh"
      assert_file_exists "${test_dir}/assets/scripts/progress-common.sh"
      assert_file_exists "${test_dir}/assets/scripts/export-images.sh"
      assert_file_exists "${test_dir}/assets/scripts/import-images.sh"
      assert_file_exists "${test_dir}/assets/scripts/image-bundle-common.sh"
      assert_file_exists "${test_dir}/assets/scripts/install-third-party.sh"
      assert_file_exists "${test_dir}/assets/scripts/prepare-runner-service-image.sh"
      assert_file_exists "${test_dir}/assets/scripts/prepare-chrono-source-cache.sh"
      assert_file_exists "${test_dir}/assets/scripts/prepare-third-party-cache.sh"
      assert_file_exists "${test_dir}/assets/scripts/prepare-builder-deps.sh"
      assert_file_exists "${test_dir}/assets/scripts/build-builder-image.sh"
      assert_file_exists "${test_dir}/assets/scripts/verify-host.sh"
      assert_file_exists "${test_dir}/assets/runner/register-runner.sh"
      assert_file_exists "${test_dir}/assets/runner/register-shell-runner.sh"
      assert_file_exists "${test_dir}/assets/runner/config.template.toml"
      assert_file_exists "${test_dir}/assets/docker/gitlab-runner/Dockerfile"
      assert_file_exists "${test_dir}/assets/docker/cuda-builder/centos7.Dockerfile"
      assert_file_exists "${test_dir}/assets/docker/cuda-builder/deps/CMake-hdf5-1.14.1-2.tar.gz"
      assert_file_exists "${test_dir}/assets/docs/offline-env-configuration.md"
      assert_file_exists "${test_dir}/assets/docs/ubuntu20-rootless-docker-compose-nvidia-offline-guide.md"
      assert_file_exists "${test_dir}/images/offline-images.tar.gz"
      assert_file_exists "${test_dir}/images/offline-images.tar.gz.images.txt"
      assert_file_exists "${test_dir}/images/offline-images.tar.gz.sha256"
      assert_contains "${test_dir}/logs/docker.log" "save registry.local/devops/cuda-builder:cuda11.7-cmake3.26-centos7 registry.local/devops/cuda-builder:cuda11.7-cmake3.26-rocky8 registry.local/devops/cuda-builder:cuda11.7-cmake3.26-ubuntu2204 registry.local/devops/gitlab-runner:alpine-v16.10.1"
      ;;
    images)
      assert_file_exists "${test_dir}/images/offline-images.tar.gz"
      assert_file_exists "${test_dir}/images/offline-images.tar.gz.images.txt"
      assert_file_exists "${test_dir}/images/offline-images.tar.gz.sha256"
      assert_not_exists "${test_dir}/assets"
      assert_contains "${test_dir}/logs/docker.log" "save registry.local/devops/cuda-builder:cuda11.7-cmake3.26-centos7 registry.local/devops/cuda-builder:cuda11.7-cmake3.26-rocky8 registry.local/devops/cuda-builder:cuda11.7-cmake3.26-ubuntu2204 registry.local/devops/gitlab-runner:alpine-v16.10.1"
      ;;
    assets)
      assert_file_exists "${test_dir}/assets/.env.example"
      assert_file_exists "${test_dir}/assets/docker-compose.yml"
      assert_file_exists "${test_dir}/assets/runner-compose.yml"
      assert_file_exists "${test_dir}/assets/examples/gitlab-ci/shared-gpu-shell-runner.yml"
      assert_file_exists "${test_dir}/assets/scripts/progress-common.sh"
      assert_file_exists "${test_dir}/assets/scripts/import-images.sh"
      assert_file_exists "${test_dir}/assets/scripts/prepare-chrono-source-cache.sh"
      assert_file_exists "${test_dir}/assets/scripts/prepare-builder-deps.sh"
      assert_file_exists "${test_dir}/assets/runner/register-runner.sh"
      assert_file_exists "${test_dir}/assets/runner/register-shell-runner.sh"
      assert_file_exists "${test_dir}/assets/docker/gitlab-runner/Dockerfile"
      assert_file_exists "${test_dir}/assets/docs/offline-env-configuration.md"
      assert_file_exists "${test_dir}/assets/docs/ubuntu20-rootless-docker-compose-nvidia-offline-guide.md"
      assert_not_exists "${test_dir}/images"
      ;;
  esac

  assert_contains "${test_dir}/bundle-manifest.txt" "bundle_mode=${mode}"
  assert_contains "${test_dir}/stdout.log" "[1/5] Loading environment"
  assert_contains "${test_dir}/stdout.log" "[5/5] Exported project integration bundle"
}

write_import_env() {
  local env_path="$1"

  cat > "${env_path}" <<'EOF'
PROJECT_BUNDLE_PATH=artifacts/project-integration-bundle.tar.gz
EOF
}

write_import_bundle() {
  local bundle_root="$1"
  local mode="$2"

  mkdir -p "${bundle_root}"

  if [[ "${mode}" == "all" || "${mode}" == "images" ]]; then
    mkdir -p "${bundle_root}/images"
    printf 'fake-image-data' | gzip -c > "${bundle_root}/images/offline-images.tar.gz"
    (
      cd "${bundle_root}/images"
      sha256sum offline-images.tar.gz > offline-images.tar.gz.sha256
    )
  fi

  if [[ "${mode}" == "all" || "${mode}" == "assets" ]]; then
    mkdir -p \
      "${bundle_root}/assets/examples/gitlab-ci" \
      "${bundle_root}/assets/docs" \
      "${bundle_root}/assets/scripts" \
      "${bundle_root}/assets/scripts/common" \
      "${bundle_root}/assets/scripts/export" \
      "${bundle_root}/assets/scripts/import" \
      "${bundle_root}/assets/runner" \
      "${bundle_root}/assets/docker/gitlab-runner" \
      "${bundle_root}/assets/docker/cuda-builder/deps"
    cp "${ROOT_DIR}/docker-compose.yml" "${bundle_root}/assets/docker-compose.yml"
    cp "${ROOT_DIR}/runner-compose.yml" "${bundle_root}/assets/runner-compose.yml"
    cp "${ROOT_DIR}/.env.example" "${bundle_root}/assets/.env.example"
    cp "${ROOT_DIR}/examples/gitlab-ci/shared-gpu-runner.yml" "${bundle_root}/assets/examples/gitlab-ci/shared-gpu-runner.yml"
    cp "${ROOT_DIR}/examples/gitlab-ci/shared-gpu-shell-runner.yml" "${bundle_root}/assets/examples/gitlab-ci/shared-gpu-shell-runner.yml"
    cp "${ROOT_DIR}/docs/offline-env-configuration.md" "${bundle_root}/assets/docs/offline-env-configuration.md"
    cp "${ROOT_DIR}/docs/ubuntu20-rootless-docker-compose-nvidia-offline-guide.md" "${bundle_root}/assets/docs/ubuntu20-rootless-docker-compose-nvidia-offline-guide.md"
    cp "${ROOT_DIR}/scripts/compose.sh" "${bundle_root}/assets/scripts/compose.sh"
    cp "${ROOT_DIR}/scripts/export-images.sh" "${bundle_root}/assets/scripts/export-images.sh"
    cp "${ROOT_DIR}/scripts/export/images.sh" "${bundle_root}/assets/scripts/export/images.sh"
    cp "${ROOT_DIR}/scripts/export/project-bundle.sh" "${bundle_root}/assets/scripts/export/project-bundle.sh"
    cp "${ROOT_DIR}/scripts/import-images.sh" "${bundle_root}/assets/scripts/import-images.sh"
    cp "${ROOT_DIR}/scripts/import/images.sh" "${bundle_root}/assets/scripts/import/images.sh"
    cp "${ROOT_DIR}/scripts/import/project-bundle.sh" "${bundle_root}/assets/scripts/import/project-bundle.sh"
    cp "${ROOT_DIR}/scripts/image-bundle-common.sh" "${bundle_root}/assets/scripts/image-bundle-common.sh"
    cp "${ROOT_DIR}/scripts/install-third-party.sh" "${bundle_root}/assets/scripts/install-third-party.sh"
    cp "${ROOT_DIR}/scripts/common/env.sh" "${bundle_root}/assets/scripts/common/env.sh"
    cp "${ROOT_DIR}/scripts/common/images.sh" "${bundle_root}/assets/scripts/common/images.sh"
    cp "${ROOT_DIR}/scripts/common/archive.sh" "${bundle_root}/assets/scripts/common/archive.sh"
    cp "${ROOT_DIR}/scripts/common/project-bundle.sh" "${bundle_root}/assets/scripts/common/project-bundle.sh"
    cp "${ROOT_DIR}/scripts/common/progress.sh" "${bundle_root}/assets/scripts/common/progress.sh"
    cp "${ROOT_DIR}/scripts/prepare-runner-service-image.sh" "${bundle_root}/assets/scripts/prepare-runner-service-image.sh"
    cp "${ROOT_DIR}/scripts/prepare-chrono-source-cache.sh" "${bundle_root}/assets/scripts/prepare-chrono-source-cache.sh"
    cp "${ROOT_DIR}/scripts/prepare-third-party-cache.sh" "${bundle_root}/assets/scripts/prepare-third-party-cache.sh"
    cp "${ROOT_DIR}/scripts/prepare-builder-deps.sh" "${bundle_root}/assets/scripts/prepare-builder-deps.sh"
    cp "${ROOT_DIR}/scripts/build-builder-image.sh" "${bundle_root}/assets/scripts/build-builder-image.sh"
    cp "${ROOT_DIR}/scripts/verify-host.sh" "${bundle_root}/assets/scripts/verify-host.sh"
    cp "${ROOT_DIR}/scripts/runner-compose.sh" "${bundle_root}/assets/scripts/runner-compose.sh"
    cp "${ROOT_DIR}/scripts/progress-common.sh" "${bundle_root}/assets/scripts/progress-common.sh"
    cp "${ROOT_DIR}/runner/register-runner.sh" "${bundle_root}/assets/runner/register-runner.sh"
    cp "${ROOT_DIR}/runner/register-shell-runner.sh" "${bundle_root}/assets/runner/register-shell-runner.sh"
    cp "${ROOT_DIR}/runner/config.template.toml" "${bundle_root}/assets/runner/config.template.toml"
    cp "${ROOT_DIR}/docker/gitlab-runner/Dockerfile" "${bundle_root}/assets/docker/gitlab-runner/Dockerfile"
    cp "${ROOT_DIR}/docker/cuda-builder/centos7.Dockerfile" "${bundle_root}/assets/docker/cuda-builder/centos7.Dockerfile"
    cp "${ROOT_DIR}/docker/cuda-builder/deps/CMake-hdf5-1.14.1-2.tar.gz" "${bundle_root}/assets/docker/cuda-builder/deps/CMake-hdf5-1.14.1-2.tar.gz"
    chmod +x "${bundle_root}/assets/scripts/"*.sh "${bundle_root}/assets/runner/register-runner.sh"
  fi
}

write_import_docker_mocks() {
  local docker_path="$1"
  local docker_compose_path="$2"

  cat > "${docker_path}" <<'EOF'
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
  cat > "${docker_compose_path}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
  chmod +x "${docker_path}" "${docker_compose_path}"
}

run_import_test() {
  local mode="$1"
  local test_dir="${TMP_DIR}/import-${mode}"
  local target_dir="${TMP_DIR}/external-project-${mode}"
  mkdir -p "${test_dir}/bin" "${test_dir}/logs"

  write_import_env "${test_dir}/.env"
  write_import_bundle "${test_dir}/bundle" "${mode}"
  tar -czf "${test_dir}/bundle.tar.gz" -C "${test_dir}/bundle" .
  (
    cd "${test_dir}"
    sha256sum bundle.tar.gz > bundle.tar.gz.sha256
  )

  write_import_docker_mocks "${test_dir}/bin/docker" "${test_dir}/bin/docker-compose"

  if [[ "${mode}" == "images" ]]; then
    TEST_LOG_FILE="${test_dir}/logs/docker.log" \
    PATH="${test_dir}/bin:${PATH}" \
    "${ROOT_DIR}/scripts/import-project-bundle.sh" \
      --env-file "${test_dir}/.env" \
      --input "${test_dir}/bundle.tar.gz" \
      --mode "${mode}" > "${test_dir}/stdout.log"
  else
    TEST_LOG_FILE="${test_dir}/logs/docker.log" \
    PATH="${test_dir}/bin:${PATH}" \
    "${ROOT_DIR}/scripts/import-project-bundle.sh" \
      --env-file "${test_dir}/.env" \
      --input "${test_dir}/bundle.tar.gz" \
      --target-dir "${target_dir}" \
      --mode "${mode}" > "${test_dir}/stdout.log"
  fi

  case "${mode}" in
    all)
      assert_contains "${test_dir}/logs/docker.log" "load"
      assert_file_exists "${target_dir}/.gpu-devops/docker-compose.yml"
      assert_file_exists "${target_dir}/.gpu-devops/examples/gitlab-ci/shared-gpu-runner.yml"
      assert_file_exists "${target_dir}/.gpu-devops/examples/gitlab-ci/shared-gpu-shell-runner.yml"
      assert_file_exists "${target_dir}/.gpu-devops/scripts/compose.sh"
      assert_file_exists "${target_dir}/.gpu-devops/scripts/common/env.sh"
      assert_file_exists "${target_dir}/.gpu-devops/scripts/export/images.sh"
      assert_file_exists "${target_dir}/.gpu-devops/scripts/import/project-bundle.sh"
      assert_file_exists "${target_dir}/.gpu-devops/scripts/progress-common.sh"
      assert_file_exists "${target_dir}/.gpu-devops/scripts/export-images.sh"
      assert_file_exists "${target_dir}/.gpu-devops/scripts/import-images.sh"
      assert_file_exists "${target_dir}/.gpu-devops/scripts/image-bundle-common.sh"
      assert_file_exists "${target_dir}/.gpu-devops/scripts/install-third-party.sh"
      assert_file_exists "${target_dir}/.gpu-devops/scripts/prepare-runner-service-image.sh"
      assert_file_exists "${target_dir}/.gpu-devops/scripts/prepare-chrono-source-cache.sh"
      assert_file_exists "${target_dir}/.gpu-devops/scripts/prepare-third-party-cache.sh"
      assert_file_exists "${target_dir}/.gpu-devops/scripts/prepare-builder-deps.sh"
      assert_file_exists "${target_dir}/.gpu-devops/scripts/build-builder-image.sh"
      assert_file_exists "${target_dir}/.gpu-devops/scripts/verify-host.sh"
      assert_file_exists "${target_dir}/.gpu-devops/runner/register-runner.sh"
      assert_file_exists "${target_dir}/.gpu-devops/runner/register-shell-runner.sh"
      assert_file_exists "${target_dir}/.gpu-devops/runner/config.template.toml"
      assert_file_exists "${target_dir}/.gpu-devops/docker/gitlab-runner/Dockerfile"
      assert_file_exists "${target_dir}/.gpu-devops/docker/cuda-builder/centos7.Dockerfile"
      assert_file_exists "${target_dir}/.gpu-devops/docker/cuda-builder/deps/CMake-hdf5-1.14.1-2.tar.gz"
      assert_file_exists "${target_dir}/.gpu-devops/docs/offline-env-configuration.md"
      assert_file_exists "${target_dir}/.gpu-devops/.env"
      assert_executable "${target_dir}/.gpu-devops/scripts/compose.sh"
      assert_contains "${target_dir}/.gpu-devops/.env" "HOST_PROJECT_DIR=${target_dir}"
      assert_contains "${target_dir}/.gpu-devops/.env" "CUDA_CXX_PROJECT_DIR=."
      assert_contains "${target_dir}/.gpu-devops/.env" "CUDA_CXX_BUILD_ROOT=.gpu-devops/artifacts/cuda-cxx-build"
      assert_contains "${target_dir}/.gpu-devops/.env" "CUDA_CXX_INSTALL_ROOT=.gpu-devops/artifacts/cuda-cxx-install"
      assert_contains "${target_dir}/.gpu-devops/.env" "CUDA_CXX_DEPS_ROOT=.gpu-devops/artifacts/deps"
      assert_contains "${target_dir}/.gpu-devops/.env" "CUDA_CXX_CMAKE_GENERATOR=Ninja"
      assert_contains "${target_dir}/.gpu-devops/.env" "CUDA_CXX_CMAKE_ARGS="
      assert_contains "${target_dir}/.gpu-devops/.env" "CUDA_CXX_BUILD_ARGS="

      TEST_LOG_FILE="${test_dir}/logs/docker.log" \
      PATH="${test_dir}/bin:${PATH}" \
      "${target_dir}/.gpu-devops/scripts/compose.sh" config

      assert_contains "${test_dir}/logs/docker.log" "compose --env-file ${target_dir}/.gpu-devops/.env -f ${target_dir}/.gpu-devops/docker-compose.yml config"

      "${target_dir}/.gpu-devops/scripts/import-images.sh" --help > "${test_dir}/import-images-help.log"
      "${target_dir}/.gpu-devops/scripts/export-images.sh" --help > "${test_dir}/export-images-help.log"
      "${target_dir}/.gpu-devops/scripts/build-builder-image.sh" --help > "${test_dir}/build-builder-help.log"
      "${target_dir}/.gpu-devops/scripts/prepare-runner-service-image.sh" --help > "${test_dir}/prepare-runner-help.log"
      "${target_dir}/.gpu-devops/scripts/prepare-chrono-source-cache.sh" --help > "${test_dir}/prepare-chrono-help.log"
      "${target_dir}/.gpu-devops/scripts/prepare-builder-deps.sh" --help > "${test_dir}/prepare-builder-deps-help.log"
      set +e
      "${target_dir}/.gpu-devops/runner/register-runner.sh" invalid > "${test_dir}/register-runner-help.log" 2>&1
      local register_status=$?
      set -e
      assert_equals "1" "${register_status}"
      assert_contains "${test_dir}/import-images-help.log" "Usage: scripts/import-images.sh"
      assert_contains "${test_dir}/export-images-help.log" "Usage: scripts/export-images.sh"
      assert_contains "${test_dir}/build-builder-help.log" "Usage: scripts/build-builder-image.sh"
      assert_contains "${test_dir}/prepare-runner-help.log" "Usage: scripts/prepare-runner-service-image.sh"
      assert_contains "${test_dir}/prepare-chrono-help.log" "Usage: scripts/prepare-chrono-source-cache.sh"
      assert_contains "${test_dir}/prepare-builder-deps-help.log" "Usage: scripts/prepare-builder-deps.sh"
      assert_contains "${test_dir}/register-runner-help.log" "Set GITLAB_URL in .env"
      ;;
    images)
      assert_contains "${test_dir}/logs/docker.log" "load"
      assert_not_exists "${target_dir}"
      ;;
    assets)
      assert_not_exists "${test_dir}/logs/docker.log"
      assert_file_exists "${target_dir}/.gpu-devops/docker-compose.yml"
      assert_file_exists "${target_dir}/.gpu-devops/examples/gitlab-ci/shared-gpu-shell-runner.yml"
      assert_file_exists "${target_dir}/.gpu-devops/scripts/progress-common.sh"
      assert_file_exists "${target_dir}/.gpu-devops/scripts/import-images.sh"
      assert_file_exists "${target_dir}/.gpu-devops/scripts/prepare-chrono-source-cache.sh"
      assert_file_exists "${target_dir}/.gpu-devops/scripts/install-third-party.sh"
      assert_file_exists "${target_dir}/.gpu-devops/scripts/prepare-third-party-cache.sh"
      assert_file_exists "${target_dir}/.gpu-devops/scripts/prepare-builder-deps.sh"
      assert_file_exists "${target_dir}/.gpu-devops/runner/register-runner.sh"
      assert_file_exists "${target_dir}/.gpu-devops/runner/register-shell-runner.sh"
      assert_file_exists "${target_dir}/.gpu-devops/docker/gitlab-runner/Dockerfile"
      assert_file_exists "${target_dir}/.gpu-devops/docs/offline-env-configuration.md"
      assert_file_exists "${target_dir}/.gpu-devops/.env"
      assert_contains "${target_dir}/.gpu-devops/.env" "CUDA_CXX_INSTALL_ROOT=.gpu-devops/artifacts/cuda-cxx-install"
      assert_contains "${target_dir}/.gpu-devops/.env" "CUDA_CXX_DEPS_ROOT=.gpu-devops/artifacts/deps"
      ;;
  esac

  assert_contains "${test_dir}/stdout.log" "[1/5] Loading environment"
  assert_contains "${test_dir}/stdout.log" "[5/5] Imported project bundle"
}

run_import_assets_with_spaces_test() {
  local test_dir="${TMP_DIR}/import-assets-with-spaces"
  local target_dir="${TMP_DIR}/external project with spaces"
  mkdir -p "${test_dir}/bin" "${test_dir}/logs"

  write_import_env "${test_dir}/.env"
  write_import_bundle "${test_dir}/bundle" assets
  tar -czf "${test_dir}/bundle.tar.gz" -C "${test_dir}/bundle" .
  (
    cd "${test_dir}"
    sha256sum bundle.tar.gz > bundle.tar.gz.sha256
  )

  write_import_docker_mocks "${test_dir}/bin/docker" "${test_dir}/bin/docker-compose"

  TEST_LOG_FILE="${test_dir}/logs/docker.log" \
  PATH="${test_dir}/bin:${PATH}" \
  "${ROOT_DIR}/scripts/import-project-bundle.sh" \
    --env-file "${test_dir}/.env" \
    --input "${test_dir}/bundle.tar.gz" \
    --target-dir "${target_dir}" \
    --mode assets > "${test_dir}/stdout.log"

  local quoted_target_dir
  quoted_target_dir="$(printf '%q' "${target_dir}")"

  assert_file_exists "${target_dir}/.gpu-devops/.env"
  assert_contains "${target_dir}/.gpu-devops/.env" "HOST_PROJECT_DIR=${quoted_target_dir}"

  bash -lc "set -euo pipefail; source '${target_dir}/.gpu-devops/.env'; [[ \"\${HOST_PROJECT_DIR}\" == '${target_dir}' ]]"
}

run_import_hash_failure_test() {
  local mode="$1"
  local test_dir="${TMP_DIR}/import-hash-failure-${mode}"
  local target_dir="${TMP_DIR}/external-project-hash-failure-${mode}"
  mkdir -p "${test_dir}/bin" "${test_dir}/logs"

  write_import_env "${test_dir}/.env"
  write_import_bundle "${test_dir}/bundle" "${mode}"
  tar -czf "${test_dir}/bundle.tar.gz" -C "${test_dir}/bundle" .
  printf '0000000000000000000000000000000000000000000000000000000000000000  bundle.tar.gz\n' > "${test_dir}/bundle.tar.gz.sha256"

  write_import_docker_mocks "${test_dir}/bin/docker" "${test_dir}/bin/docker-compose"

  set +e
  if [[ "${mode}" == "images" ]]; then
    TEST_LOG_FILE="${test_dir}/logs/docker.log" \
    PATH="${test_dir}/bin:${PATH}" \
    "${ROOT_DIR}/scripts/import-project-bundle.sh" \
      --env-file "${test_dir}/.env" \
      --input "${test_dir}/bundle.tar.gz" \
      --mode "${mode}" >"${test_dir}/stdout.log" 2>"${test_dir}/stderr.log"
  else
    TEST_LOG_FILE="${test_dir}/logs/docker.log" \
    PATH="${test_dir}/bin:${PATH}" \
    "${ROOT_DIR}/scripts/import-project-bundle.sh" \
      --env-file "${test_dir}/.env" \
      --input "${test_dir}/bundle.tar.gz" \
      --target-dir "${target_dir}" \
      --mode "${mode}" >"${test_dir}/stdout.log" 2>"${test_dir}/stderr.log"
  fi
  local status=$?
  set -e

  assert_equals "1" "${status}"
  assert_contains "${test_dir}/stderr.log" "SHA256 verification failed"
  assert_not_exists "${target_dir}"
}

run_export_test all
run_export_test images
run_export_test assets
run_import_test all
run_import_test images
run_import_test assets
run_import_assets_with_spaces_test
run_import_hash_failure_test all
run_import_hash_failure_test images

echo "project integration bundle tests passed"
