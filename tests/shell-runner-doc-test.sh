#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

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
    fail "missing expected content"
  fi
}

assert_file_exists() {
  local path="$1"
  [[ -f "${path}" ]] || fail "expected file to exist: ${path}"
}

assert_file_exists "${ROOT_DIR}/runner/register-shell-runner.sh"
assert_file_exists "${ROOT_DIR}/examples/gitlab-ci/shared-gpu-shell-runner.yml"

assert_contains "${ROOT_DIR}/examples/gitlab-ci/shared-gpu-shell-runner.yml" "  - test"
assert_contains "${ROOT_DIR}/examples/gitlab-ci/shared-gpu-shell-runner.yml" "  - deploy"
assert_contains "${ROOT_DIR}/examples/gitlab-ci/shared-gpu-shell-runner.yml" '.gpu-devops/scripts/compose.sh run --rm "cuda-cxx-${BUILD_PLATFORM}"'
assert_contains "${ROOT_DIR}/examples/gitlab-ci/shared-gpu-shell-runner.yml" "BUILD_PLATFORM: centos7"
assert_contains "${ROOT_DIR}/examples/gitlab-ci/shared-gpu-shell-runner.yml" "CUDA_CXX_BUILD_ROOT: .gpu-devops/artifacts/cuda-cxx-build"
assert_contains "${ROOT_DIR}/examples/gitlab-ci/shared-gpu-shell-runner.yml" "CUDA_CXX_INSTALL_ROOT: .gpu-devops/artifacts/cuda-cxx-install"
assert_contains "${ROOT_DIR}/examples/gitlab-ci/shared-gpu-shell-runner.yml" 'cuda-cxx-${BUILD_PLATFORM}'
assert_contains "${ROOT_DIR}/examples/gitlab-ci/shared-gpu-shell-runner.yml" 'if [[ ! " centos7 rocky8 ubuntu2204 " =~ " ${BUILD_PLATFORM} " ]]; then'
assert_contains "${ROOT_DIR}/examples/gitlab-ci/shared-gpu-shell-runner.yml" "shell-runner:verify:linux"
assert_contains "${ROOT_DIR}/examples/gitlab-ci/shared-gpu-shell-runner.yml" "shell-runner:build:linux"
assert_contains "${ROOT_DIR}/examples/gitlab-ci/shared-gpu-shell-runner.yml" "shell-runner:test:linux"
assert_contains "${ROOT_DIR}/examples/gitlab-ci/shared-gpu-shell-runner.yml" "shell-runner:deploy:linux"
assert_contains "${ROOT_DIR}/examples/gitlab-ci/shared-gpu-shell-runner.yml" '${CUDA_CXX_BUILD_ROOT}/${BUILD_PLATFORM}/'
assert_contains "${ROOT_DIR}/examples/gitlab-ci/shared-gpu-shell-runner.yml" '${CUDA_CXX_INSTALL_ROOT}/${BUILD_PLATFORM}/'
assert_contains "${ROOT_DIR}/examples/gitlab-ci/shared-gpu-shell-runner.yml" "artifacts:"
assert_contains "${ROOT_DIR}/examples/gitlab-ci/shared-gpu-shell-runner.yml" "needs:"
assert_contains "${ROOT_DIR}/examples/gitlab-ci/shared-gpu-shell-runner.yml" 'bash ./scripts/deploy-centos7.sh "${CUDA_CXX_INSTALL_ROOT}/${BUILD_PLATFORM}"'
assert_contains "${ROOT_DIR}/examples/gitlab-ci/shared-gpu-shell-runner.yml" 'case "${BUILD_PLATFORM}" in'
assert_contains "${ROOT_DIR}/examples/gitlab-ci/shared-gpu-shell-runner.yml" "./scripts/deploy-centos7.sh"
assert_contains "${ROOT_DIR}/examples/gitlab-ci/shared-gpu-shell-runner.yml" "./scripts/deploy-rocky8.sh"
assert_contains "${ROOT_DIR}/examples/gitlab-ci/shared-gpu-shell-runner.yml" "./scripts/deploy-ubuntu2204.sh"
assert_contains "${ROOT_DIR}/examples/gitlab-ci/shared-gpu-shell-runner.yml" "shell-runner:build:windows"
assert_contains "${ROOT_DIR}/examples/gitlab-ci/shared-gpu-shell-runner.yml" "shell-runner:test:windows"
assert_contains "${ROOT_DIR}/examples/gitlab-ci/shared-gpu-shell-runner.yml" "shell-runner:deploy:windows"
if grep -Fq -- "BUILD_OS:" "${ROOT_DIR}/examples/gitlab-ci/shared-gpu-shell-runner.yml"; then
  fail "BUILD_OS should not appear in shared-gpu-shell-runner.yml"
fi
if grep -Fq -- "cmake --install" "${ROOT_DIR}/examples/gitlab-ci/shared-gpu-shell-runner.yml"; then
  fail "cmake --install should be handled by docker-compose.yml, not the shell-runner example"
fi
assert_contains "${ROOT_DIR}/docker-compose.yml" "CUDA_CXX_INSTALL_ROOT"
assert_contains "${ROOT_DIR}/docker-compose.yml" 'cmake --install "$$CUDA_CXX_BUILD_ROOT/$$BUILD_PLATFORM" --prefix "$$CUDA_CXX_INSTALL_ROOT/$$BUILD_PLATFORM"'
assert_contains "${ROOT_DIR}/docs/gitlab-ci-multi-environment.md" "shared-gpu-shell-runner.yml"
assert_contains "${ROOT_DIR}/docs/gitlab-ci-multi-environment.md" '.gpu-devops/scripts/compose.sh run --rm "cuda-cxx-${BUILD_PLATFORM}"'
assert_contains "${ROOT_DIR}/docs/usage.en.md" "register-shell-runner.sh"
assert_contains "${ROOT_DIR}/docs/usage.zh-CN.md" "register-shell-runner.sh"
assert_contains "${ROOT_DIR}/docs/usage.en.md" "offline-env-configuration.md"
assert_contains "${ROOT_DIR}/docs/usage.zh-CN.md" "offline-env-configuration.md"

echo "shell runner doc tests passed"
