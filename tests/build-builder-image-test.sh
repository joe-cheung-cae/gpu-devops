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

run_with_mock_docker() {
  local env_file="$1"
  local log_file="$2"
  shift 2

  local mock_bin="${TMP_DIR}/bin"
  mkdir -p "${mock_bin}"

  cat > "${mock_bin}/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${TEST_LOG_FILE:?}"
exit 0
EOF
  chmod +x "${mock_bin}/docker"

  TEST_LOG_FILE="${log_file}" PATH="${mock_bin}:${PATH}" \
    "${ROOT_DIR}/scripts/build-builder-image.sh" --env-file "${env_file}" "$@"
}

ENV_FILE="${TMP_DIR}/.env"
cat > "${ENV_FILE}" <<'EOF'
BUILDER_IMAGE_FAMILY=registry.local/devops/cuda-builder:cuda11.7-cmake3.26
BUILDER_DEFAULT_PLATFORM=centos7
BUILDER_PLATFORMS=centos7,rocky8,ubuntu2204
BUILDER_IMAGE=registry.local/devops/cuda-builder:cuda11.7-cmake3.26-centos7
EOF

default_log="${TMP_DIR}/default.log"
run_with_mock_docker "${ENV_FILE}" "${default_log}"
assert_contains "${default_log}" "-t registry.local/devops/cuda-builder:cuda11.7-cmake3.26-centos7"
assert_contains "${default_log}" "-f ${ROOT_DIR}/docker/cuda-builder/centos7.Dockerfile"

ubuntu_log="${TMP_DIR}/ubuntu.log"
run_with_mock_docker "${ENV_FILE}" "${ubuntu_log}" --platform ubuntu2204
assert_contains "${ubuntu_log}" "-t registry.local/devops/cuda-builder:cuda11.7-cmake3.26-ubuntu2204"
assert_contains "${ubuntu_log}" "-f ${ROOT_DIR}/docker/cuda-builder/ubuntu2204.Dockerfile"

all_log="${TMP_DIR}/all.log"
run_with_mock_docker "${ENV_FILE}" "${all_log}" --all-platforms
assert_contains "${all_log}" "-t registry.local/devops/cuda-builder:cuda11.7-cmake3.26-centos7"
assert_contains "${all_log}" "-f ${ROOT_DIR}/docker/cuda-builder/centos7.Dockerfile"
assert_contains "${all_log}" "-t registry.local/devops/cuda-builder:cuda11.7-cmake3.26-rocky8"
assert_contains "${all_log}" "-f ${ROOT_DIR}/docker/cuda-builder/rocky8.Dockerfile"
assert_contains "${all_log}" "-t registry.local/devops/cuda-builder:cuda11.7-cmake3.26-ubuntu2204"
assert_contains "${all_log}" "-f ${ROOT_DIR}/docker/cuda-builder/ubuntu2204.Dockerfile"

echo "build builder image tests passed"
