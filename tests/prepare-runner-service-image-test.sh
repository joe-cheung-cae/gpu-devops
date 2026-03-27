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
RUNNER_SERVICE_IMAGE=tf-particles/devops/gitlab-runner:alpine-v16.10.1
RUNNER_SERVICE_SOURCE_IMAGE=gitlab/gitlab-runner:alpine-v16.10.1
RUNNER_SERVICE_IMAGE_PREPARE_MODE=retag
EOF
}

write_docker_mock() {
  local docker_path="$1"

  cat > "${docker_path}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
LOG_FILE="${TEST_LOG_FILE:?}"
printf '%s\n' "$*" >> "${LOG_FILE}"

case "${1:-}" in
  pull|tag|build)
    exit 0
    ;;
  image)
    shift
    if [[ "${1:-}" == "inspect" ]]; then
      exit 0
    fi
    ;;
esac

exit 0
EOF
  chmod +x "${docker_path}"
}

run_default_retag_test() {
  local test_dir="${TMP_DIR}/retag-default"
  mkdir -p "${test_dir}/bin"

  write_base_env "${test_dir}/.env"
  write_docker_mock "${test_dir}/bin/docker"

  TEST_LOG_FILE="${test_dir}/docker.log" \
  PATH="${test_dir}/bin:${PATH}" \
  "${ROOT_DIR}/scripts/prepare-runner-service-image.sh" --env-file "${test_dir}/.env" >"${test_dir}/stdout.log"

  assert_contains "${test_dir}/docker.log" "pull gitlab/gitlab-runner:alpine-v16.10.1"
  assert_contains "${test_dir}/docker.log" "tag gitlab/gitlab-runner:alpine-v16.10.1 tf-particles/devops/gitlab-runner:alpine-v16.10.1"
  assert_contains "${test_dir}/docker.log" "image inspect tf-particles/devops/gitlab-runner:alpine-v16.10.1"
  assert_contains "${test_dir}/stdout.log" "[1/4] Loading environment"
  assert_contains "${test_dir}/stdout.log" "[3/4] Preparing runner service image via retag"
  assert_contains "${test_dir}/stdout.log" "Prepared Runner service image tf-particles/devops/gitlab-runner:alpine-v16.10.1 via retag from gitlab/gitlab-runner:alpine-v16.10.1"
}

run_build_mode_test() {
  local test_dir="${TMP_DIR}/build-mode"
  mkdir -p "${test_dir}/bin"

  write_base_env "${test_dir}/.env"
  write_docker_mock "${test_dir}/bin/docker"

  TEST_LOG_FILE="${test_dir}/docker.log" \
  PATH="${test_dir}/bin:${PATH}" \
  "${ROOT_DIR}/scripts/prepare-runner-service-image.sh" --env-file "${test_dir}/.env" --mode build >"${test_dir}/stdout.log"

  assert_contains "${test_dir}/docker.log" "build -t tf-particles/devops/gitlab-runner:alpine-v16.10.1 --build-arg RUNNER_SERVICE_SOURCE_IMAGE=gitlab/gitlab-runner:alpine-v16.10.1 -f ${ROOT_DIR}/docker/gitlab-runner/Dockerfile ${ROOT_DIR}/docker/gitlab-runner"
  assert_contains "${test_dir}/docker.log" "image inspect tf-particles/devops/gitlab-runner:alpine-v16.10.1"
  assert_contains "${test_dir}/stdout.log" "[3/4] Preparing runner service image via build"
  assert_contains "${test_dir}/stdout.log" "Prepared Runner service image tf-particles/devops/gitlab-runner:alpine-v16.10.1 via build from gitlab/gitlab-runner:alpine-v16.10.1"
}

run_override_test() {
  local test_dir="${TMP_DIR}/override"
  mkdir -p "${test_dir}/bin"

  write_base_env "${test_dir}/.env"
  write_docker_mock "${test_dir}/bin/docker"

  TEST_LOG_FILE="${test_dir}/docker.log" \
  PATH="${test_dir}/bin:${PATH}" \
  "${ROOT_DIR}/scripts/prepare-runner-service-image.sh" \
    --env-file "${test_dir}/.env" \
    --source-image registry.internal/base/gitlab-runner:custom \
    --target-image registry.internal/team/gitlab-runner:offline >"${test_dir}/stdout.log"

  assert_contains "${test_dir}/docker.log" "pull registry.internal/base/gitlab-runner:custom"
  assert_contains "${test_dir}/docker.log" "tag registry.internal/base/gitlab-runner:custom registry.internal/team/gitlab-runner:offline"
  assert_contains "${test_dir}/docker.log" "image inspect registry.internal/team/gitlab-runner:offline"
  assert_contains "${test_dir}/stdout.log" "[2/4] Resolving runner service image source and target"
  assert_contains "${test_dir}/stdout.log" "Prepared Runner service image registry.internal/team/gitlab-runner:offline via retag from registry.internal/base/gitlab-runner:custom"
}

run_default_retag_test
run_build_mode_test
run_override_test

echo "prepare runner service image tests passed"
