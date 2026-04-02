#!/usr/bin/env bash
set -euo pipefail

TOOLKIT_ROOT="${TOOLKIT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# shellcheck disable=SC1091
source "${TOOLKIT_ROOT}/scripts/common/third-party-registry.sh"

: "${DEPS_ROOT:=${HOME}/deps}"
: "${THIRD_PARTY_CACHE_ROOT:=$(dirname "${DEPS_ROOT}")/cache}"

DEPS_CSV="$(third_party_all_deps_csv)"

usage() {
  cat <<'EOF'
Usage: third_party/install-third-party.sh [--deps chrono,eigen3,openmpi,hdf5,h5engine,muparserx]

Install the requested third-party dependencies in registry order using local archives only.
EOF
}

while [[ $# -gt 0 ]]; do
  case "${1}" in
    --deps)
      DEPS_CSV="${2:?Missing value for --deps}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: ${1}" >&2
      usage >&2
      exit 1
      ;;
  esac
done

RESOLVED_DEPS_CSV="$(third_party_resolve_dep_order "${DEPS_CSV}" linux)"
IFS=',' read -r -a DEPS <<< "${RESOLVED_DEPS_CSV}"

mkdir -p "${DEPS_ROOT}" "${THIRD_PARTY_CACHE_ROOT}"
printf 'Installing third-party dependencies: %s\n' "${RESOLVED_DEPS_CSV}"

for dep in "${DEPS[@]}"; do
  dep_command="$(third_party_linux_install_command "${dep}" "${DEPS_ROOT}" "${THIRD_PARTY_CACHE_ROOT}" "${TOOLKIT_ROOT}")"
  /bin/bash -lc "${dep_command}"
done
