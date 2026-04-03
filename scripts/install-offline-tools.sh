#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PREFIX=""

usage() {
  cat <<'EOF'
Usage: scripts/install-offline-tools.sh --prefix PATH

Installs the builder image toolchain into the given prefix.
The installed tree is self-contained and includes bin wrappers, scripts,
Dockerfiles, example env files, docs, and vendored build assets.
EOF
}

while [[ $# -gt 0 ]]; do
  case "${1}" in
    --prefix)
      PREFIX="${2:?Missing value for --prefix}"
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

if [[ -z "${PREFIX}" ]]; then
  echo "Missing required --prefix argument" >&2
  usage >&2
  exit 1
fi

mkdir -p "${PREFIX}"

copy_tree() {
  local source_path="$1"
  local target_path="$2"

  if [[ -d "${source_path}" ]]; then
    mkdir -p "${target_path}"
    cp -a "${source_path}/." "${target_path}/"
  else
    mkdir -p "$(dirname "${target_path}")"
    cp -a "${source_path}" "${target_path}"
  fi
}

copy_tree "${ROOT_DIR}/scripts" "${PREFIX}/scripts"
copy_tree "${ROOT_DIR}/docker" "${PREFIX}/docker"
copy_tree "${ROOT_DIR}/docs" "${PREFIX}/docs"
copy_tree "${ROOT_DIR}/third_party/cache" "${PREFIX}/third_party/cache"
copy_tree "${ROOT_DIR}/README.md" "${PREFIX}/README.md"
copy_tree "${ROOT_DIR}/.env.example" "${PREFIX}/.env.example"
copy_tree "${ROOT_DIR}/.env.example" "${PREFIX}/.env"

mkdir -p "${PREFIX}/bin" "${PREFIX}/artifacts"

write_wrapper() {
  local wrapper_path="$1"
  local target_path="$2"

  cat > "${wrapper_path}" <<EOF
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
PREFIX="\$(cd "\${SCRIPT_DIR}/.." && pwd)"
exec "\${PREFIX}/${target_path}" "\$@"
EOF
  chmod +x "${wrapper_path}"
}

write_wrapper "${PREFIX}/bin/build-builder-image.sh" "scripts/build-builder-image.sh"
write_wrapper "${PREFIX}/bin/export-images.sh" "scripts/export/images.sh"
write_wrapper "${PREFIX}/bin/import-images.sh" "scripts/import/images.sh"

echo "Installed offline builder tools into ${PREFIX}"
