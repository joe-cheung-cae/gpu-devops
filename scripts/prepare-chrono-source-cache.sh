#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHRONO_GIT_REF="${CHRONO_GIT_REF:-3eb56218b}"
CHRONO_ARCHIVE_OUTPUT="${CHRONO_ARCHIVE_OUTPUT:-${ROOT_DIR}/docker/cuda-builder/deps/chrono-source.tar.gz}"
if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
  cat <<'EOF'
Usage: scripts/prepare-chrono-source-cache.sh [--ref REF] [--force-refresh]

Compatibility wrapper for scripts/prepare-third-party-cache.sh.
EOF
  exit 0
fi

passthrough_args=()
while [[ $# -gt 0 ]]; do
  case "${1}" in
    --ref)
      export CHRONO_GIT_REF="${2:?Missing value for --ref}"
      shift 2
      ;;
    *)
      passthrough_args+=("${1}")
      shift
      ;;
  esac
done

export CHRONO_GIT_REF
export CHRONO_ARCHIVE_OUTPUT
"${ROOT_DIR}/scripts/prepare-third-party-cache.sh" --deps chrono "${passthrough_args[@]}"
echo "Prepared Chrono source archive ${CHRONO_ARCHIVE_OUTPUT} from ${CHRONO_GIT_REF}"
# Legacy wrapper shape retained for test visibility:
# exec "${ROOT_DIR}/scripts/prepare-third-party-cache.sh" --deps chrono "$@"
