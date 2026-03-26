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
  mkdir -p "${test_dir}/bin" "${test_dir}/runner"

  write_base_env "${test_dir}/.env"
  write_docker_mock "${test_dir}/bin/docker"

  cp "${ROOT_DIR}/runner/register-runner.sh" "${test_dir}/runner/register-runner.sh"
  chmod +x "${test_dir}/runner/register-runner.sh"

  (
    cd "${test_dir}"
    mkdir -p runner/config runner/cache
    TEST_LOG_FILE="${test_dir}/docker.log" PATH="${test_dir}/bin:${PATH}" ./runner/register-runner.sh gpu
  )

  assert_contains "${test_dir}/docker.log" "run --rm -it --name gitlab-runner-devops-register"
}

run_override_name_test() {
  local test_dir="${TMP_DIR}/override-name"
  mkdir -p "${test_dir}/bin" "${test_dir}/runner"

  write_base_env "${test_dir}/.env"
  cat >> "${test_dir}/.env" <<'EOF'
RUNNER_REGISTRATION_CONTAINER_NAME=custom-runner-register
EOF
  write_docker_mock "${test_dir}/bin/docker"

  cp "${ROOT_DIR}/runner/register-runner.sh" "${test_dir}/runner/register-runner.sh"
  chmod +x "${test_dir}/runner/register-runner.sh"

  (
    cd "${test_dir}"
    mkdir -p runner/config runner/cache
    TEST_LOG_FILE="${test_dir}/docker.log" PATH="${test_dir}/bin:${PATH}" ./runner/register-runner.sh multi
  )

  assert_contains "${test_dir}/docker.log" "run --rm -it --name custom-runner-register"
}

run_default_name_test
run_override_name_test

echo "register runner tests passed"
