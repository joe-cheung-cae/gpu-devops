#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck disable=SC1091
source "${ROOT_DIR}/scripts/common/third-party-registry.sh"

ENV_FILE="${ROOT_DIR}/.env"
HOST="linux"
PLATFORM=""
DEPS_CSV="$(third_party_all_deps_csv)"
FORCE_REFRESH=false
OFFLINE_ONLY=false
WINDOWS_THIRD_PARTY_ROOT="${ROOT_DIR}/third_party/windows-msvc"
WINDOWS_THIRD_PARTY_CACHE_ROOT="${ROOT_DIR}/third_party/cache"
MSMPI_SDK_ARCHIVE="${WINDOWS_THIRD_PARTY_CACHE_ROOT}/msmpi-sdk.zip"
MSMPI_REDIST_ARCHIVE="${WINDOWS_THIRD_PARTY_CACHE_ROOT}/msmpi-redist.zip"

usage() {
  cat <<'EOF'
Usage: scripts/install-third-party.sh [--env-file PATH] [--host linux|windows] [--platform centos7|rocky8|ubuntu2204] [--deps chrono,eigen3,openmpi,hdf5,h5engine,muparserx] [--offline-only] [--force-refresh]

Prepare third-party caches and install them into the project-local third_party tree for Linux via docker compose, or for Windows/MSVC on the host.
EOF
}

while [[ $# -gt 0 ]]; do
  case "${1}" in
    --env-file)
      ENV_FILE="${2:?Missing value for --env-file}"
      shift 2
      ;;
    --host)
      HOST="${2:?Missing value for --host}"
      shift 2
      ;;
    --platform)
      PLATFORM="${2:?Missing value for --platform}"
      shift 2
      ;;
    --deps)
      DEPS_CSV="${2:?Missing value for --deps}"
      shift 2
      ;;
    --offline-only)
      OFFLINE_ONLY=true
      shift
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

run_cache_prepare() {
  local args=(--deps "${DEPS_CSV}")
  [[ "${OFFLINE_ONLY}" == "true" ]] && args+=(--offline-only)
  [[ "${FORCE_REFRESH}" == "true" ]] && args+=(--force-refresh)
  "${ROOT_DIR}/scripts/prepare-third-party-cache.sh" "${args[@]}"
}

run_linux_install() {
  local args=(--env-file "${ENV_FILE}" --deps "${DEPS_CSV}")
  [[ -n "${PLATFORM}" ]] && args+=(--platform "${PLATFORM}")
  "${ROOT_DIR}/scripts/prepare-builder-deps.sh" "${args[@]}"
}

find_vswhere() {
  if command -v vswhere >/dev/null 2>&1; then
    command -v vswhere
    return 0
  fi
  local path="/c/Program Files (x86)/Microsoft Visual Studio/Installer/vswhere.exe"
  if [[ -x "${path}" ]]; then
    printf '%s\n' "${path}"
    return 0
  fi
  return 1
}

require_windows_tools() {
  command -v cmake >/dev/null 2>&1
  command -v ninja >/dev/null 2>&1
  find_vswhere >/dev/null 2>&1 || {
    echo "vswhere is required to locate the MSVC environment." >&2
    exit 1
  }
}

run_msvc_command() {
  local command_text="$1"
  local vswhere_bin vcvars_path
  vswhere_bin="$(find_vswhere)"
  vcvars_path="$("${vswhere_bin}" -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -find VC/Auxiliary/Build/vcvars64.bat | tr -d '\r')"
  if [[ -z "${vcvars_path}" ]]; then
    echo "Unable to locate vcvars64.bat via vswhere." >&2
    exit 1
  fi
  cmd.exe //c "\"${vcvars_path}\" && ${command_text}"
}

extract_archive() {
  local archive_path="$1"
  local destination="$2"
  rm -rf "${destination}"
  mkdir -p "${destination}"
  case "${archive_path}" in
    *.zip)
      powershell -NoProfile -ExecutionPolicy Bypass -Command "Expand-Archive -Path '${archive_path}' -DestinationPath '${destination}' -Force" >/dev/null
      ;;
    *.tar.gz)
      tar -xzf "${archive_path}" -C "${destination}"
      ;;
    *)
      echo "Unsupported archive type: ${archive_path}" >&2
      exit 1
      ;;
  esac
}

install_windows_eigen3() {
  local deps_root="$1"
  local archive_path="${WINDOWS_THIRD_PARTY_CACHE_ROOT}/eigen-3.4.0.tar.gz"
  local source_root="${deps_root}/eigen3-src"
  local install_root="${deps_root}/eigen3-install"
  extract_archive "${archive_path}" "${source_root}"
  rm -rf "${install_root}"
  mkdir -p "${install_root}/include"
  cp -R "${source_root}/eigen-3.4.0/." "${install_root}/include/"
}

install_windows_msmpi() {
  local deps_root="$1"
  local install_root="${deps_root}/msmpi-install"
  mkdir -p "${install_root}"
  if [[ -f "${MSMPI_SDK_ARCHIVE}" ]]; then
    extract_archive "${MSMPI_SDK_ARCHIVE}" "${install_root}/sdk"
  fi
  if [[ -f "${MSMPI_REDIST_ARCHIVE}" ]]; then
    extract_archive "${MSMPI_REDIST_ARCHIVE}" "${install_root}/redist"
  fi
}

install_windows_chrono() {
  local deps_root="$1"
  install_windows_cmake_dep "chrono" "${WINDOWS_THIRD_PARTY_CACHE_ROOT}/chrono-source.tar.gz" "." "${deps_root}/chrono-install" "-DBUILD_BENCHMARKING=OFF -DBUILD_DEMOS=OFF -DBUILD_TESTING=OFF -DUSE_BULLET_DOUBLE=ON -DUSE_SIMD=OFF" "${deps_root}"
}

install_windows_hdf5() {
  local deps_root="$1"
  install_windows_cmake_dep "hdf5" "${WINDOWS_THIRD_PARTY_CACHE_ROOT}/CMake-hdf5-1.14.1-2.tar.gz" "CMake-hdf5-1.14.1-2/hdf5-1.14.1-2" "${deps_root}/hdf5-install" "" "${deps_root}"
}

install_windows_muparserx() {
  local deps_root="$1"
  install_windows_cmake_dep "muparserx" "${WINDOWS_THIRD_PARTY_CACHE_ROOT}/muparserx-source.tar.gz" "." "${deps_root}/muparserx-install" "" "${deps_root}"
}

install_windows_h5engine() {
  echo "Dependency 'h5engine' does not support host 'windows'" >&2
  exit 1
}

install_windows_cmake_dep() {
  local dep_name="$1"
  local source_archive="$2"
  local source_subdir="$3"
  local install_prefix="$4"
  local cmake_args="$5"
  local deps_root="$6"
  local source_root="${deps_root}/${dep_name}-src"
  extract_archive "${source_archive}" "${source_root}"
  run_msvc_command "cmake -S \"${source_root}/${source_subdir}\" -B \"${source_root}/build\" -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=\"${install_prefix}\" ${cmake_args} && cmake --build \"${source_root}/build\" --parallel 6 && cmake --install \"${source_root}/build\""
}

run_windows_install() {
  local deps_root="${WINDOWS_THIRD_PARTY_ROOT}"
  local dep install_handler
  require_windows_tools
  mkdir -p "${deps_root}"

  IFS=',' read -r -a deps <<< "$(third_party_resolve_dep_order "${DEPS_CSV}" windows)"
  for dep in "${deps[@]}"; do
    dep="${dep//[[:space:]]/}"
    install_handler="$(third_party_windows_install_function "${dep}")"
    "${install_handler}" "${deps_root}"
  done
}

run_cache_prepare

case "${HOST}" in
  linux)
    run_linux_install
    ;;
  windows)
    run_windows_install
    ;;
  *)
    echo "Unsupported host: ${HOST}" >&2
    echo "Expected --host linux|windows" >&2
    exit 1
    ;;
esac
