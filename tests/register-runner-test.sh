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

write_base_env() {
  local env_path="$1"
  cat > "${env_path}" <<'EOF'
GITLAB_URL=http://gitlab.example.internal
RUNNER_REGISTRATION_TOKEN=test-token
RUNNER_EXECUTOR=docker
RUNNER_DOCKER_IMAGE=registry.local/devops/cuda-builder:cuda11.7-cmake3.26-centos7
RUNNER_SERVICE_IMAGE=gitlab/gitlab-runner:alpine-v16.10.1
RUNNER_DESCRIPTION_PREFIX=shared-gpu
RUNNER_TAG_LIST=gpu,cuda,cuda-11
RUNNER_MULTI_TAG_LIST=gpu-multi,cuda,cuda-11
RUNNER_LOCKED=false
RUNNER_RUN_UNTAGGED=false
RUNNER_ACCESS_LEVEL=not_protected
RUNNER_GPU_CONCURRENCY=2
RUNNER_MULTI_GPU_CONCURRENCY=1
EOF
}

write_docker_mock() {
  local docker_path="$1"
  cat > "${docker_path}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
LOG_FILE="${TEST_LOG_FILE:?}"
printf '%s\n' "$*" >> "${LOG_FILE}"
exit 0
EOF
  chmod +x "${docker_path}"
}

run_default_name_test() {
  local test_dir="${TMP_DIR}/default-name"
  mkdir -p "${test_dir}/bin" "${test_dir}/runner" "${test_dir}/scripts"

  write_base_env "${test_dir}/.env"
  write_docker_mock "${test_dir}/bin/docker"

  cp "${ROOT_DIR}/runner/register-runner.sh" "${test_dir}/runner/register-runner.sh"
  cp "${ROOT_DIR}/scripts/progress-common.sh" "${test_dir}/scripts/progress-common.sh"
  chmod +x "${test_dir}/runner/register-runner.sh"

  (
    cd "${test_dir}"
    mkdir -p runner/config runner/cache
    TEST_LOG_FILE="${test_dir}/docker.log" PATH="${test_dir}/bin:${PATH}" ./runner/register-runner.sh gpu > "${test_dir}/stdout.log"
  )

  assert_contains "${test_dir}/docker.log" "run --rm -it --name gitlab-runner-devops-register"
  assert_contains "${test_dir}/stdout.log" "[1/4] Loading runner configuration"
  assert_contains "${test_dir}/stdout.log" "[4/4] Runner registration command completed"
}

run_override_name_test() {
  local test_dir="${TMP_DIR}/override-name"
  mkdir -p "${test_dir}/bin" "${test_dir}/runner" "${test_dir}/scripts"

  write_base_env "${test_dir}/.env"
  cat >> "${test_dir}/.env" <<'EOF'
RUNNER_REGISTRATION_CONTAINER_NAME=custom-runner-register
EOF
  write_docker_mock "${test_dir}/bin/docker"

  cp "${ROOT_DIR}/runner/register-runner.sh" "${test_dir}/runner/register-runner.sh"
  cp "${ROOT_DIR}/scripts/progress-common.sh" "${test_dir}/scripts/progress-common.sh"
  chmod +x "${test_dir}/runner/register-runner.sh"

  (
    cd "${test_dir}"
    mkdir -p runner/config runner/cache
    TEST_LOG_FILE="${test_dir}/docker.log" PATH="${test_dir}/bin:${PATH}" ./runner/register-runner.sh multi > "${test_dir}/stdout.log"
  )

  assert_contains "${test_dir}/docker.log" "run --rm -it --name custom-runner-register"
  assert_contains "${test_dir}/stdout.log" "[2/4] Resolving runner mode multi"
}

run_default_name_test
run_override_name_test

echo "register runner tests passed"
