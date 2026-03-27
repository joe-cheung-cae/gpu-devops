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

cat > "${TMP_DIR}/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  --version)
    echo "Docker version test"
    ;;
  compose)
    if [[ "${2:-}" == "version" ]]; then
      echo "Docker Compose version test"
    fi
    ;;
  info)
    echo '{"nvidia":{"path":"nvidia-container-runtime"}}'
    ;;
esac
EOF

cat > "${TMP_DIR}/nvidia-smi" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "NVIDIA-SMI test"
EOF

chmod +x "${TMP_DIR}/docker" "${TMP_DIR}/nvidia-smi"

PATH="${TMP_DIR}:${PATH}" "${ROOT_DIR}/scripts/verify-host.sh" > "${TMP_DIR}/stdout.log"

assert_contains "${TMP_DIR}/stdout.log" "[1/5] Checking Docker"
assert_contains "${TMP_DIR}/stdout.log" "[2/5] Checking Compose"
assert_contains "${TMP_DIR}/stdout.log" "[3/5] Checking NVIDIA driver"
assert_contains "${TMP_DIR}/stdout.log" "[4/5] Checking NVIDIA Container Toolkit runtime"
assert_contains "${TMP_DIR}/stdout.log" "[5/5] Host verification passed"

echo "verify host tests passed"
