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

write_third_party_prepare_mocks() {
  local bin_dir="$1"
  local git_path="${bin_dir}/git"
  local curl_path="${bin_dir}/curl"

  cat > "${git_path}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
LOG_FILE="${TEST_LOG_FILE:?}"
printf 'git %s\n' "$*" >> "${LOG_FILE}"
case "${1:-}" in
  clone)
    local_dest="${@: -1}"
    mkdir -p "${local_dest}/.git"
    printf 'placeholder\n' > "${local_dest}/placeholder.txt"
    exit 0
    ;;
  fetch|checkout)
    exit 0
    ;;
  rev-parse)
    if [[ "${2:-}" == "--verify" && "${3:-}" == "FETCH_HEAD" ]]; then
      printf 'deadbeef\n'
      exit 0
    fi
    exit 0
    ;;
esac
exit 0
EOF
  chmod +x "${git_path}"

  cat > "${curl_path}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
LOG_FILE="${TEST_LOG_FILE:?}"
printf 'curl %s\n' "$*" >> "${LOG_FILE}"
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
printf 'placeholder archive\n' > "${output}"
EOF
  chmod +x "${curl_path}"
}

run_export_third_party_cache_test() {
  local test_dir="${TMP_DIR}/export-third-party-cache"
  local repo_dir="${test_dir}/repo"
  mkdir -p "${test_dir}/bin" "${test_dir}/logs"

  mkdir -p \
    "${repo_dir}/docker/cuda-builder/deps" \
    "${repo_dir}/examples/gitlab-ci" \
    "${repo_dir}/runner" \
    "${repo_dir}/scripts/common" \
    "${repo_dir}/scripts/export" \
    "${repo_dir}/scripts/import" \
    "${repo_dir}/docs"
  cp -a "${ROOT_DIR}/.env.example" "${repo_dir}/.env.example"
  cp -a "${ROOT_DIR}/README.md" "${repo_dir}/README.md"
  cp -a "${ROOT_DIR}/AGENTS.md" "${repo_dir}/AGENTS.md"
  cp -a "${ROOT_DIR}/docker-compose.yml" "${repo_dir}/docker-compose.yml"
  cp -a "${ROOT_DIR}/examples/gitlab-ci/shared-gpu-shell-runner.yml" "${repo_dir}/examples/gitlab-ci/shared-gpu-shell-runner.yml"
  cp -a "${ROOT_DIR}/runner/register-shell-runner.sh" "${repo_dir}/runner/register-shell-runner.sh"
  cp -a "${ROOT_DIR}/scripts/common/env.sh" "${repo_dir}/scripts/common/env.sh"
  cp -a "${ROOT_DIR}/scripts/common/images.sh" "${repo_dir}/scripts/common/images.sh"
  cp -a "${ROOT_DIR}/scripts/common/archive.sh" "${repo_dir}/scripts/common/archive.sh"
  cp -a "${ROOT_DIR}/scripts/common/docker-rootless-common.sh" "${repo_dir}/scripts/common/docker-rootless-common.sh"
  cp -a "${ROOT_DIR}/scripts/common/project-bundle.sh" "${repo_dir}/scripts/common/project-bundle.sh"
  cp -a "${ROOT_DIR}/scripts/common/progress.sh" "${repo_dir}/scripts/common/progress.sh"
  cp -a "${ROOT_DIR}/scripts/common/third-party-registry.sh" "${repo_dir}/scripts/common/third-party-registry.sh"
  cp -a "${ROOT_DIR}/scripts/export/images.sh" "${repo_dir}/scripts/export/images.sh"
  cp -a "${ROOT_DIR}/scripts/export/project-bundle.sh" "${repo_dir}/scripts/export/project-bundle.sh"
  cp -a "${ROOT_DIR}/scripts/import/images.sh" "${repo_dir}/scripts/import/images.sh"
  cp -a "${ROOT_DIR}/scripts/import/project-bundle.sh" "${repo_dir}/scripts/import/project-bundle.sh"
  cp -a "${ROOT_DIR}/scripts/compose.sh" "${repo_dir}/scripts/compose.sh"
  cp -a "${ROOT_DIR}/scripts/install-third-party.sh" "${repo_dir}/scripts/install-third-party.sh"
  cp -a "${ROOT_DIR}/scripts/prepare-third-party-cache.sh" "${repo_dir}/scripts/prepare-third-party-cache.sh"
  cp -a "${ROOT_DIR}/scripts/prepare-builder-deps.sh" "${repo_dir}/scripts/prepare-builder-deps.sh"
  cp -a "${ROOT_DIR}/scripts/build-builder-image.sh" "${repo_dir}/scripts/build-builder-image.sh"
  cp -a "${ROOT_DIR}/scripts/verify-host.sh" "${repo_dir}/scripts/verify-host.sh"
  cp -a "${ROOT_DIR}/docs/offline-env-configuration.md" "${repo_dir}/docs/offline-env-configuration.md"
  cp -a "${ROOT_DIR}/docs/ubuntu20-rootless-docker-compose-nvidia-offline-guide.md" "${repo_dir}/docs/ubuntu20-rootless-docker-compose-nvidia-offline-guide.md"
  cp -a "${ROOT_DIR}/docs/tutorial.en.md" "${repo_dir}/docs/tutorial.en.md"
  cp -a "${ROOT_DIR}/docs/tutorial.zh-CN.md" "${repo_dir}/docs/tutorial.zh-CN.md"
  cp -a "${ROOT_DIR}/docs/operations.md" "${repo_dir}/docs/operations.md"
  cp -a "${ROOT_DIR}/docs/self-check.md" "${repo_dir}/docs/self-check.md"
  cp -a "${ROOT_DIR}/docs/gitlab-ci-multi-environment.md" "${repo_dir}/docs/gitlab-ci-multi-environment.md"
  cp -a "${ROOT_DIR}/docs/usage.en.md" "${repo_dir}/docs/usage.en.md"
  cp -a "${ROOT_DIR}/docs/usage.zh-CN.md" "${repo_dir}/docs/usage.zh-CN.md"
  cp -a "${ROOT_DIR}/docker/cuda-builder/centos7.Dockerfile" "${repo_dir}/docker/cuda-builder/centos7.Dockerfile"
  cp -a "${ROOT_DIR}/docker/cuda-builder/rocky8.Dockerfile" "${repo_dir}/docker/cuda-builder/rocky8.Dockerfile"
  cp -a "${ROOT_DIR}/docker/cuda-builder/ubuntu2204.Dockerfile" "${repo_dir}/docker/cuda-builder/ubuntu2204.Dockerfile"
  printf 'placeholder\n' > "${repo_dir}/docker/cuda-builder/deps/cmake-3.26.0-linux-x86_64.tar.gz"
  printf 'placeholder\n' > "${repo_dir}/docker/cuda-builder/deps/CMake-hdf5-1.14.1-2.tar.gz"
  printf 'placeholder\n' > "${repo_dir}/docker/cuda-builder/deps/h5engine-sph.tar.gz"
  printf 'placeholder\n' > "${repo_dir}/docker/cuda-builder/deps/h5engine-dem.tar.gz"
  rm -f \
    "${repo_dir}/docker/cuda-builder/deps/chrono-source.tar.gz" \
    "${repo_dir}/docker/cuda-builder/deps/eigen-3.4.0.tar.gz" \
    "${repo_dir}/docker/cuda-builder/deps/openmpi-4.1.6.tar.gz" \
    "${repo_dir}/docker/cuda-builder/deps/muparserx-source.tar.gz"

  write_export_env "${test_dir}/.env"
  write_export_docker_mock "${test_dir}/bin/docker"
  write_third_party_prepare_mocks "${test_dir}/bin"

  TEST_LOG_FILE="${test_dir}/logs/prepare.log" \
  PATH="${test_dir}/bin:${PATH}" \
  "${repo_dir}/scripts/export/project-bundle.sh" \
    --env-file "${test_dir}/.env" \
    --output "${test_dir}/bundle.tar.gz" \
    --mode assets > "${test_dir}/stdout.log"

  assert_file_exists "${repo_dir}/docker/cuda-builder/deps/chrono-source.tar.gz"
  assert_file_exists "${repo_dir}/docker/cuda-builder/deps/eigen-3.4.0.tar.gz"
  assert_file_exists "${repo_dir}/docker/cuda-builder/deps/openmpi-4.1.6.tar.gz"
  assert_file_exists "${repo_dir}/docker/cuda-builder/deps/muparserx-source.tar.gz"
  assert_contains "${test_dir}/logs/prepare.log" "git clone https://github.com/projectchrono/chrono.git"
  assert_contains "${test_dir}/logs/prepare.log" "curl -fsSL https://gitlab.com/libeigen/eigen/-/archive/3.4.0/eigen-3.4.0.tar.gz -o ${repo_dir}/docker/cuda-builder/deps/eigen-3.4.0.tar.gz"
  assert_contains "${test_dir}/logs/prepare.log" "curl -fsSL https://download.open-mpi.org/release/open-mpi/v4.1/openmpi-4.1.6.tar.gz -o ${repo_dir}/docker/cuda-builder/deps/openmpi-4.1.6.tar.gz"
  assert_contains "${test_dir}/logs/prepare.log" "git clone https://github.com/joe-cheung-cae/muparserx.git"
  assert_file_exists "${repo_dir}/docker/cuda-builder/deps/cmake-3.26.0-linux-x86_64.tar.gz"
  assert_not_contains "${test_dir}/logs/prepare.log" "https://github.com/Kitware/CMake/releases/download/v3.26.0/cmake-3.26.0-linux-x86_64.tar.gz"
  tar -tzf "${test_dir}/bundle.tar.gz" | grep -Fq "assets/docker/cuda-builder/deps/chrono-source.tar.gz"
  tar -tzf "${test_dir}/bundle.tar.gz" | grep -Fq "assets/docker/cuda-builder/deps/eigen-3.4.0.tar.gz"
  tar -tzf "${test_dir}/bundle.tar.gz" | grep -Fq "assets/docker/cuda-builder/deps/openmpi-4.1.6.tar.gz"
  tar -tzf "${test_dir}/bundle.tar.gz" | grep -Fq "assets/docker/cuda-builder/deps/muparserx-source.tar.gz"
}

run_export_test() {
  local mode="$1"
  local test_dir="${TMP_DIR}/export-${mode}"
  mkdir -p "${test_dir}/bin" "${test_dir}/logs"

  write_export_env "${test_dir}/.env"
  write_export_docker_mock "${test_dir}/bin/docker"

  TEST_LOG_FILE="${test_dir}/logs/docker.log" \
  PATH="${test_dir}/bin:${PATH}" \
  "${ROOT_DIR}/scripts/export/project-bundle.sh" --env-file "${test_dir}/.env" --output "${test_dir}/bundle.tar.gz" --mode "${mode}" > "${test_dir}/stdout.log"

  assert_file_exists "${test_dir}/bundle.tar.gz"
  assert_file_exists "${test_dir}/bundle.tar.gz.sha256"
  tar -xzf "${test_dir}/bundle.tar.gz" -C "${test_dir}"

  case "${mode}" in
    all)
      assert_file_exists "${test_dir}/assets/.env.example"
      assert_file_exists "${test_dir}/assets/docker-compose.yml"
      assert_file_exists "${test_dir}/assets/examples/gitlab-ci/shared-gpu-shell-runner.yml"
      assert_file_exists "${test_dir}/assets/scripts/compose.sh"
      assert_file_exists "${test_dir}/assets/scripts/common/env.sh"
      assert_file_exists "${test_dir}/assets/scripts/common/third-party-registry.sh"
      assert_file_exists "${test_dir}/assets/scripts/export/images.sh"
      assert_file_exists "${test_dir}/assets/scripts/import/project-bundle.sh"
      assert_file_exists "${test_dir}/assets/scripts/import/images.sh"
      assert_file_exists "${test_dir}/assets/scripts/common/progress.sh"
      assert_file_exists "${test_dir}/assets/scripts/common/docker-rootless-common.sh"
      assert_file_exists "${test_dir}/assets/scripts/install-third-party.sh"
      assert_file_exists "${test_dir}/assets/scripts/prepare-third-party-cache.sh"
      assert_file_exists "${test_dir}/assets/scripts/prepare-builder-deps.sh"
      assert_file_exists "${test_dir}/assets/scripts/build-builder-image.sh"
      assert_file_exists "${test_dir}/assets/scripts/verify-host.sh"
      assert_file_exists "${test_dir}/assets/runner/register-shell-runner.sh"
      assert_file_exists "${test_dir}/assets/docker/cuda-builder/centos7.Dockerfile"
      assert_file_exists "${test_dir}/assets/docker/cuda-builder/deps/cmake-3.26.0-linux-x86_64.tar.gz"
      assert_file_exists "${test_dir}/assets/docker/cuda-builder/deps/CMake-hdf5-1.14.1-2.tar.gz"
      assert_file_exists "${test_dir}/assets/docs/offline-env-configuration.md"
      assert_file_exists "${test_dir}/assets/docs/ubuntu20-rootless-docker-compose-nvidia-offline-guide.md"
      assert_file_exists "${test_dir}/images/offline-images.tar.gz"
      assert_file_exists "${test_dir}/images/offline-images.tar.gz.images.txt"
      assert_file_exists "${test_dir}/images/offline-images.tar.gz.sha256"
      assert_contains "${test_dir}/logs/docker.log" "save registry.local/devops/cuda-builder:cuda11.7-cmake3.26-centos7 registry.local/devops/cuda-builder:cuda11.7-cmake3.26-rocky8 registry.local/devops/cuda-builder:cuda11.7-cmake3.26-ubuntu2204"
      ;;
    images)
      assert_file_exists "${test_dir}/images/offline-images.tar.gz"
      assert_file_exists "${test_dir}/images/offline-images.tar.gz.images.txt"
      assert_file_exists "${test_dir}/images/offline-images.tar.gz.sha256"
      assert_not_exists "${test_dir}/assets"
      assert_contains "${test_dir}/logs/docker.log" "save registry.local/devops/cuda-builder:cuda11.7-cmake3.26-centos7 registry.local/devops/cuda-builder:cuda11.7-cmake3.26-rocky8 registry.local/devops/cuda-builder:cuda11.7-cmake3.26-ubuntu2204"
      ;;
    assets)
      assert_file_exists "${test_dir}/assets/.env.example"
      assert_file_exists "${test_dir}/assets/docker-compose.yml"
      assert_file_exists "${test_dir}/assets/examples/gitlab-ci/shared-gpu-shell-runner.yml"
      assert_file_exists "${test_dir}/assets/scripts/common/progress.sh"
      assert_file_exists "${test_dir}/assets/scripts/import/images.sh"
      assert_file_exists "${test_dir}/assets/scripts/common/docker-rootless-common.sh"
      assert_file_exists "${test_dir}/assets/scripts/prepare-builder-deps.sh"
      assert_file_exists "${test_dir}/assets/runner/register-shell-runner.sh"
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
      "${bundle_root}/assets/docker/cuda-builder/deps"
    cp "${ROOT_DIR}/docker-compose.yml" "${bundle_root}/assets/docker-compose.yml"
    cp "${ROOT_DIR}/.env.example" "${bundle_root}/assets/.env.example"
    cp "${ROOT_DIR}/examples/gitlab-ci/shared-gpu-shell-runner.yml" "${bundle_root}/assets/examples/gitlab-ci/shared-gpu-shell-runner.yml"
    cp "${ROOT_DIR}/docs/offline-env-configuration.md" "${bundle_root}/assets/docs/offline-env-configuration.md"
    cp "${ROOT_DIR}/docs/ubuntu20-rootless-docker-compose-nvidia-offline-guide.md" "${bundle_root}/assets/docs/ubuntu20-rootless-docker-compose-nvidia-offline-guide.md"
    cp "${ROOT_DIR}/scripts/compose.sh" "${bundle_root}/assets/scripts/compose.sh"
    cp "${ROOT_DIR}/scripts/export/images.sh" "${bundle_root}/assets/scripts/export/images.sh"
    cp "${ROOT_DIR}/scripts/export/project-bundle.sh" "${bundle_root}/assets/scripts/export/project-bundle.sh"
    cp "${ROOT_DIR}/scripts/import/images.sh" "${bundle_root}/assets/scripts/import/images.sh"
    cp "${ROOT_DIR}/scripts/import/project-bundle.sh" "${bundle_root}/assets/scripts/import/project-bundle.sh"
    cp "${ROOT_DIR}/scripts/install-third-party.sh" "${bundle_root}/assets/scripts/install-third-party.sh"
    cp "${ROOT_DIR}/scripts/common/env.sh" "${bundle_root}/assets/scripts/common/env.sh"
    cp "${ROOT_DIR}/scripts/common/images.sh" "${bundle_root}/assets/scripts/common/images.sh"
    cp "${ROOT_DIR}/scripts/common/archive.sh" "${bundle_root}/assets/scripts/common/archive.sh"
    cp "${ROOT_DIR}/scripts/common/docker-rootless-common.sh" "${bundle_root}/assets/scripts/common/docker-rootless-common.sh"
    cp "${ROOT_DIR}/scripts/common/third-party-registry.sh" "${bundle_root}/assets/scripts/common/third-party-registry.sh"
    cp "${ROOT_DIR}/scripts/common/project-bundle.sh" "${bundle_root}/assets/scripts/common/project-bundle.sh"
    cp "${ROOT_DIR}/scripts/common/progress.sh" "${bundle_root}/assets/scripts/common/progress.sh"
    cp "${ROOT_DIR}/scripts/prepare-third-party-cache.sh" "${bundle_root}/assets/scripts/prepare-third-party-cache.sh"
    cp "${ROOT_DIR}/scripts/prepare-builder-deps.sh" "${bundle_root}/assets/scripts/prepare-builder-deps.sh"
    cp "${ROOT_DIR}/scripts/build-builder-image.sh" "${bundle_root}/assets/scripts/build-builder-image.sh"
    cp "${ROOT_DIR}/scripts/verify-host.sh" "${bundle_root}/assets/scripts/verify-host.sh"
    cp "${ROOT_DIR}/runner/register-shell-runner.sh" "${bundle_root}/assets/runner/register-shell-runner.sh"
    cp "${ROOT_DIR}/docker/cuda-builder/centos7.Dockerfile" "${bundle_root}/assets/docker/cuda-builder/centos7.Dockerfile"
    cp "${ROOT_DIR}/docker/cuda-builder/deps/cmake-3.26.0-linux-x86_64.tar.gz" "${bundle_root}/assets/docker/cuda-builder/deps/cmake-3.26.0-linux-x86_64.tar.gz"
    cp "${ROOT_DIR}/docker/cuda-builder/deps/CMake-hdf5-1.14.1-2.tar.gz" "${bundle_root}/assets/docker/cuda-builder/deps/CMake-hdf5-1.14.1-2.tar.gz"
    chmod +x "${bundle_root}/assets/scripts/"*.sh
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
if [[ "${1:-}" == "info" ]]; then
  printf 'name=rootless\n'
  exit 0
fi
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
    "${ROOT_DIR}/scripts/import/project-bundle.sh" \
      --env-file "${test_dir}/.env" \
      --input "${test_dir}/bundle.tar.gz" \
      --mode "${mode}" > "${test_dir}/stdout.log"
  else
    TEST_LOG_FILE="${test_dir}/logs/docker.log" \
    PATH="${test_dir}/bin:${PATH}" \
    "${ROOT_DIR}/scripts/import/project-bundle.sh" \
      --env-file "${test_dir}/.env" \
      --input "${test_dir}/bundle.tar.gz" \
      --target-dir "${target_dir}" \
      --mode "${mode}" > "${test_dir}/stdout.log"
  fi

  case "${mode}" in
    all)
      assert_contains "${test_dir}/logs/docker.log" "load"
      assert_file_exists "${target_dir}/.gpu-devops/docker-compose.yml"
      assert_file_exists "${target_dir}/.gpu-devops/examples/gitlab-ci/shared-gpu-shell-runner.yml"
      assert_file_exists "${target_dir}/.gpu-devops/scripts/compose.sh"
      assert_file_exists "${target_dir}/.gpu-devops/scripts/common/env.sh"
      assert_file_exists "${target_dir}/.gpu-devops/scripts/common/third-party-registry.sh"
      assert_file_exists "${target_dir}/.gpu-devops/scripts/export/images.sh"
      assert_file_exists "${target_dir}/.gpu-devops/scripts/import/project-bundle.sh"
      assert_file_exists "${target_dir}/.gpu-devops/scripts/import/images.sh"
      assert_file_exists "${target_dir}/.gpu-devops/scripts/common/progress.sh"
      assert_file_exists "${target_dir}/.gpu-devops/scripts/common/docker-rootless-common.sh"
      assert_file_exists "${target_dir}/.gpu-devops/scripts/install-third-party.sh"
      assert_file_exists "${target_dir}/.gpu-devops/scripts/prepare-third-party-cache.sh"
      assert_file_exists "${target_dir}/.gpu-devops/scripts/prepare-builder-deps.sh"
      assert_file_exists "${target_dir}/.gpu-devops/scripts/build-builder-image.sh"
      assert_file_exists "${target_dir}/.gpu-devops/scripts/verify-host.sh"
      assert_file_exists "${target_dir}/.gpu-devops/runner/register-shell-runner.sh"
      assert_file_exists "${target_dir}/.gpu-devops/docker/cuda-builder/centos7.Dockerfile"
      assert_file_exists "${target_dir}/.gpu-devops/docker/cuda-builder/deps/cmake-3.26.0-linux-x86_64.tar.gz"
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

      "${target_dir}/.gpu-devops/scripts/import/images.sh" --help > "${test_dir}/import-images-help.log"
      "${target_dir}/.gpu-devops/scripts/export/images.sh" --help > "${test_dir}/export-images-help.log"
      "${target_dir}/.gpu-devops/scripts/build-builder-image.sh" --help > "${test_dir}/build-builder-help.log"
      "${target_dir}/.gpu-devops/scripts/prepare-third-party-cache.sh" --deps chrono --help > "${test_dir}/prepare-chrono-help.log"
      "${target_dir}/.gpu-devops/scripts/prepare-builder-deps.sh" --help > "${test_dir}/prepare-builder-deps-help.log"
      assert_contains "${test_dir}/import-images-help.log" "Usage: scripts/import/images.sh"
      assert_contains "${test_dir}/export-images-help.log" "Usage: scripts/export/images.sh"
      assert_contains "${test_dir}/build-builder-help.log" "Usage: scripts/build-builder-image.sh"
      assert_contains "${test_dir}/prepare-chrono-help.log" "Usage: scripts/prepare-third-party-cache.sh"
      assert_contains "${test_dir}/prepare-builder-deps-help.log" "Usage: scripts/prepare-builder-deps.sh"
      ;;
    images)
      assert_contains "${test_dir}/logs/docker.log" "load"
      assert_not_exists "${target_dir}"
      ;;
    assets)
      assert_not_exists "${test_dir}/logs/docker.log"
      assert_file_exists "${target_dir}/.gpu-devops/docker-compose.yml"
      assert_file_exists "${target_dir}/.gpu-devops/examples/gitlab-ci/shared-gpu-shell-runner.yml"
      assert_file_exists "${target_dir}/.gpu-devops/scripts/common/progress.sh"
      assert_file_exists "${target_dir}/.gpu-devops/scripts/common/third-party-registry.sh"
      assert_file_exists "${target_dir}/.gpu-devops/scripts/import/images.sh"
      assert_file_exists "${target_dir}/.gpu-devops/scripts/common/docker-rootless-common.sh"
      assert_file_exists "${target_dir}/.gpu-devops/scripts/install-third-party.sh"
      assert_file_exists "${target_dir}/.gpu-devops/scripts/prepare-third-party-cache.sh"
      assert_file_exists "${target_dir}/.gpu-devops/scripts/prepare-builder-deps.sh"
      assert_file_exists "${target_dir}/.gpu-devops/runner/register-shell-runner.sh"
      assert_file_exists "${target_dir}/.gpu-devops/docker/cuda-builder/deps/cmake-3.26.0-linux-x86_64.tar.gz"
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
  "${ROOT_DIR}/scripts/import/project-bundle.sh" \
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
    "${ROOT_DIR}/scripts/import/project-bundle.sh" \
      --env-file "${test_dir}/.env" \
      --input "${test_dir}/bundle.tar.gz" \
      --mode "${mode}" >"${test_dir}/stdout.log" 2>"${test_dir}/stderr.log"
  else
    TEST_LOG_FILE="${test_dir}/logs/docker.log" \
    PATH="${test_dir}/bin:${PATH}" \
    "${ROOT_DIR}/scripts/import/project-bundle.sh" \
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

run_export_third_party_cache_test
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
