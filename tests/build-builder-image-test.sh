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

run_with_mock_docker() {
  local env_file="$1"
  local log_file="$2"
  local stdout_file="$3"
  shift 3

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
    "${ROOT_DIR}/scripts/build-builder-image.sh" --env-file "${env_file}" "$@" > "${stdout_file}"
}

DEFAULT_CUDA_VERSION="11.7.1"
DEFAULT_IMAGE_FAMILY="tf-particles/devops/cuda-builder:cuda${DEFAULT_CUDA_VERSION}-cmake3.26"

ENV_FILE="${TMP_DIR}/.env"
cat > "${ENV_FILE}" <<'EOF'
BUILDER_CUDA_VERSION=11.7.1
BUILDER_DEFAULT_PLATFORM=centos7
BUILDER_PLATFORMS=centos7,rocky8,ubuntu2204
EOF

default_log="${TMP_DIR}/default.log"
default_stdout="${TMP_DIR}/default.stdout"
run_with_mock_docker "${ENV_FILE}" "${default_log}" "${default_stdout}"
assert_contains "${default_log}" "--build-arg CUDA_VERSION=11.7.1"
assert_contains "${default_log}" "-t ${DEFAULT_IMAGE_FAMILY}-centos7"
assert_contains "${default_log}" "-f ${ROOT_DIR}/docker/cuda-builder/centos7.Dockerfile"
assert_contains "${default_stdout}" "[1/5] Loading environment"
assert_contains "${default_stdout}" "[2/5] Resolving target platforms"
assert_contains "${default_stdout}" "[3/5] Validating platform Dockerfiles"
assert_contains "${default_stdout}" "[4/5] Building platform image centos7"
assert_contains "${default_stdout}" "[5/5] Completed builder image build workflow"

override_log="${TMP_DIR}/override.log"
override_stdout="${TMP_DIR}/override.stdout"
run_with_mock_docker "${ENV_FILE}" "${override_log}" "${override_stdout}" --platform ubuntu2204 --cuda-version 12.4.1
assert_contains "${override_log}" "--build-arg CUDA_VERSION=12.4.1"
assert_contains "${override_log}" "-t tf-particles/devops/cuda-builder:cuda12.4.1-cmake3.26-ubuntu2204"
assert_contains "${override_log}" "-f ${ROOT_DIR}/docker/cuda-builder/ubuntu2204.Dockerfile"
assert_contains "${override_stdout}" "[4/5] Building platform image ubuntu2204"

ubuntu_log="${TMP_DIR}/ubuntu.log"
ubuntu_stdout="${TMP_DIR}/ubuntu.stdout"
run_with_mock_docker "${ENV_FILE}" "${ubuntu_log}" "${ubuntu_stdout}" --platform ubuntu2204
assert_contains "${ubuntu_log}" "--build-arg CUDA_VERSION=11.7.1"
assert_contains "${ubuntu_log}" "-t ${DEFAULT_IMAGE_FAMILY}-ubuntu2204"
assert_contains "${ubuntu_log}" "-f ${ROOT_DIR}/docker/cuda-builder/ubuntu2204.Dockerfile"
assert_contains "${ubuntu_stdout}" "[4/5] Building platform image ubuntu2204"

all_log="${TMP_DIR}/all.log"
all_stdout="${TMP_DIR}/all.stdout"
run_with_mock_docker "${ENV_FILE}" "${all_log}" "${all_stdout}" --all-platforms
assert_contains "${all_log}" "--build-arg CUDA_VERSION=11.7.1"
assert_contains "${all_log}" "-t ${DEFAULT_IMAGE_FAMILY}-centos7"
assert_contains "${all_log}" "-f ${ROOT_DIR}/docker/cuda-builder/centos7.Dockerfile"
assert_contains "${all_log}" "-t ${DEFAULT_IMAGE_FAMILY}-rocky8"
assert_contains "${all_log}" "-f ${ROOT_DIR}/docker/cuda-builder/rocky8.Dockerfile"
assert_contains "${all_log}" "-t ${DEFAULT_IMAGE_FAMILY}-ubuntu2204"
assert_contains "${all_log}" "-f ${ROOT_DIR}/docker/cuda-builder/ubuntu2204.Dockerfile"
assert_contains "${all_stdout}" "[4/5] Building platform image centos7"
assert_contains "${all_stdout}" "[4/5] Building platform image rocky8"
assert_contains "${all_stdout}" "[4/5] Building platform image ubuntu2204"

assert_contains "${ROOT_DIR}/docker/cuda-builder/centos7.Dockerfile" 'third_party/cache/cmake-3.26.0-linux-x86_64.tar.gz'
assert_contains "${ROOT_DIR}/docker/cuda-builder/rocky8.Dockerfile" 'third_party/cache/cmake-3.26.0-linux-x86_64.tar.gz'
assert_contains "${ROOT_DIR}/docker/cuda-builder/ubuntu2204.Dockerfile" 'third_party/cache/cmake-3.26.0-linux-x86_64.tar.gz'
assert_contains "${ROOT_DIR}/docker/cuda-builder/centos7.Dockerfile" 'tar -xzf /tmp/deps/cmake-3.26.0-linux-x86_64.tar.gz -C /usr/local --strip-components=1'
assert_contains "${ROOT_DIR}/docker/cuda-builder/rocky8.Dockerfile" 'tar -xzf /tmp/deps/cmake-3.26.0-linux-x86_64.tar.gz -C /usr/local --strip-components=1'
assert_contains "${ROOT_DIR}/docker/cuda-builder/ubuntu2204.Dockerfile" 'tar -xzf /tmp/deps/cmake-3.26.0-linux-x86_64.tar.gz -C /usr/local --strip-components=1'

assert_contains "${ROOT_DIR}/.env.example" 'BUILDER_CUDA_VERSION='
assert_contains "${ROOT_DIR}/.env.example" 'BUILDER_DEFAULT_PLATFORM='
assert_contains "${ROOT_DIR}/.env.example" 'BUILDER_PLATFORMS='
assert_not_contains "${ROOT_DIR}/.env.example" 'BUILDER_IMAGE_FAMILY='
assert_not_contains "${ROOT_DIR}/.env.example" 'BUILDER_IMAGE='
assert_not_contains "${ROOT_DIR}/.env.example" 'CUDA_CXX_PROJECT_DIR='
assert_not_contains "${ROOT_DIR}/.env.example" 'IMAGE_ARCHIVE_PATH='
assert_not_contains "${ROOT_DIR}/.env.example" 'RUNNER_'

assert_contains "${ROOT_DIR}/README.md" 'CUDA Builder Images'
assert_contains "${ROOT_DIR}/README.md" 'scripts/export/images.sh'
assert_contains "${ROOT_DIR}/README.md" 'scripts/install-offline-tools.sh'
assert_contains "${ROOT_DIR}/docs/platform-contract.md" 'cuda11.7.1-cmake3.26'
assert_contains "${ROOT_DIR}/docs/platform-contract.md" 'BUILDER_CUDA_VERSION'
assert_contains "${ROOT_DIR}/docs/platform-contract.md" 'third_party/cache/cmake-3.26.0-linux-x86_64.tar.gz'
