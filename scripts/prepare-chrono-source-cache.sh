#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

CHRONO_GIT_URL="${CHRONO_GIT_URL:-https://github.com/projectchrono/chrono.git}"
CHRONO_GIT_REF="${CHRONO_GIT_REF:-3eb56218b}"
CHRONO_CACHE_DIR="${CHRONO_CACHE_DIR:-${ROOT_DIR}/docker/cuda-builder/deps/chrono-cache}"
CHRONO_ARCHIVE_OUTPUT="${CHRONO_ARCHIVE_OUTPUT:-${ROOT_DIR}/docker/cuda-builder/deps/chrono-source.tar.gz}"
FORCE_REFRESH=false

usage() {
  cat <<'EOF'
Usage: scripts/prepare-chrono-source-cache.sh [--ref REF] [--force-refresh]

Prepares a local Project Chrono source cache and writes docker/cuda-builder/deps/chrono-source.tar.gz.
The archive contains the checked-out source tree without .git metadata.
EOF
}

while [[ $# -gt 0 ]]; do
  case "${1}" in
    --ref)
      CHRONO_GIT_REF="${2:?Missing value for --ref}"
      shift 2
      ;;
    --force-refresh)
      FORCE_REFRESH=true
      shift
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

WORKTREE_DIR="${CHRONO_CACHE_DIR}/worktree"
STAGE_DIR="$(mktemp -d)"
trap 'rm -rf "${STAGE_DIR}"' EXIT

if [[ "${FORCE_REFRESH}" == "true" ]]; then
  rm -rf "${WORKTREE_DIR}"
fi

mkdir -p "${CHRONO_CACHE_DIR}" "$(dirname "${CHRONO_ARCHIVE_OUTPUT}")"

if [[ ! -d "${WORKTREE_DIR}/.git" ]]; then
  git clone "${CHRONO_GIT_URL}" "${WORKTREE_DIR}"
fi

(
  cd "${WORKTREE_DIR}"
  git fetch origin --tags
  git checkout --force "${CHRONO_GIT_REF}"
)

rsync -a --delete --exclude='.git' --exclude='build' "${WORKTREE_DIR}/" "${STAGE_DIR}/"
printf '%s\n' "${CHRONO_GIT_REF}" > "${STAGE_DIR}/.chrono-source-ref"

rm -f "${CHRONO_ARCHIVE_OUTPUT}"
tar -czf "${CHRONO_ARCHIVE_OUTPUT}" -C "${STAGE_DIR}" .

echo "Prepared Chrono source archive ${CHRONO_ARCHIVE_OUTPUT} from ${CHRONO_GIT_REF}"
