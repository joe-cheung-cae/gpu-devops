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

write_base_env() {
  local env_path="$1"
  local shell_user="$2"
  cat > "${env_path}" <<EOF
GITLAB_URL=http://gitlab.example.internal
RUNNER_REGISTRATION_TOKEN=test-token
RUNNER_SHELL_EXECUTOR=shell
RUNNER_SHELL_USER=${shell_user}
SHELL_RUNNER_DEFAULT_PLATFORM=centos7
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

write_runner_mock() {
  local runner_path="$1"
  cat > "${runner_path}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
LOG_FILE="${TEST_LOG_FILE:?}"
printf '%s\n' "$*" >> "${LOG_FILE}"
exit 0
EOF
  chmod +x "${runner_path}"
}

run_gpu_mode_test() {
  local test_dir="${TMP_DIR}/gpu-mode"
  mkdir -p "${test_dir}/bin" "${test_dir}/runner" "${test_dir}/scripts" "${test_dir}/home"
  local shell_user
  shell_user="$(id -un)"

  write_base_env "${test_dir}/.env" "${shell_user}"
  write_runner_mock "${test_dir}/bin/gitlab-runner"

  cp "${ROOT_DIR}/runner/register-shell-runner.sh" "${test_dir}/runner/register-shell-runner.sh"
  cp "${ROOT_DIR}/scripts/progress-common.sh" "${test_dir}/scripts/progress-common.sh"
  chmod +x "${test_dir}/runner/register-shell-runner.sh"

  (
    cd "${test_dir}"
    HOME="${test_dir}/home" TEST_LOG_FILE="${test_dir}/runner.log" PATH="${test_dir}/bin:${PATH}" ./runner/register-shell-runner.sh gpu > "${test_dir}/stdout.log"
  )

  assert_contains "${test_dir}/runner.log" "register"
  assert_contains "${test_dir}/runner.log" "--executor"
  assert_contains "${test_dir}/runner.log" "shell"
  assert_contains "${test_dir}/runner.log" "--description"
  assert_contains "${test_dir}/runner.log" "shared-gpu-gpu"
  assert_contains "${test_dir}/runner.log" "--tag-list"
  assert_contains "${test_dir}/runner.log" "gpu,cuda,cuda-11"
  assert_not_contains "${test_dir}/runner.log" "--docker-image"
  assert_not_contains "${test_dir}/runner.log" "--docker-runtime"
  assert_not_contains "${test_dir}/runner.log" "--docker-volumes"
  assert_contains "${test_dir}/stdout.log" "[4/4] Shell runner registration command completed"
}

run_multi_mode_tls_test() {
  local test_dir="${TMP_DIR}/multi-mode-tls"
  mkdir -p "${test_dir}/bin" "${test_dir}/runner" "${test_dir}/scripts" "${test_dir}/certs" "${test_dir}/home"
  local shell_user
  shell_user="$(id -un)"

  write_base_env "${test_dir}/.env" "${shell_user}"
  cat >> "${test_dir}/.env" <<'EOF'
GITLAB_URL=https://172.18.20.5
RUNNER_TLS_CA_FILE=certs/gitlab-ca.crt
EOF
  printf 'fake-ca' > "${test_dir}/certs/gitlab-ca.crt"
  write_runner_mock "${test_dir}/bin/gitlab-runner"

  cp "${ROOT_DIR}/runner/register-shell-runner.sh" "${test_dir}/runner/register-shell-runner.sh"
  cp "${ROOT_DIR}/scripts/progress-common.sh" "${test_dir}/scripts/progress-common.sh"
  chmod +x "${test_dir}/runner/register-shell-runner.sh"

  (
    cd "${test_dir}"
    HOME="${test_dir}/home" TEST_LOG_FILE="${test_dir}/runner.log" PATH="${test_dir}/bin:${PATH}" ./runner/register-shell-runner.sh multi > "${test_dir}/stdout.log"
  )

  assert_contains "${test_dir}/runner.log" "--executor"
  assert_contains "${test_dir}/runner.log" "shell"
  assert_contains "${test_dir}/runner.log" "--tag-list"
  assert_contains "${test_dir}/runner.log" "gpu-multi,cuda,cuda-11"
  assert_contains "${test_dir}/runner.log" "--tls-ca-file"
  assert_contains "${test_dir}/runner.log" "${test_dir}/home/.gitlab-runner/certs/172.18.20.5.crt"
  assert_contains "${test_dir}/home/.gitlab-runner/certs/172.18.20.5.crt" "fake-ca"
}

run_gpu_mode_test
run_multi_mode_tls_test

echo "register shell runner tests passed"
