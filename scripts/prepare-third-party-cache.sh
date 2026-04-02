#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck disable=SC1091
source "${ROOT_DIR}/scripts/common/third-party-registry.sh"

DEPS_CSV="$(third_party_all_deps_csv)"
FORCE_REFRESH=false
OFFLINE_ONLY=false

CHRONO_GIT_URL="${CHRONO_GIT_URL:-https://github.com/projectchrono/chrono.git}"
CHRONO_GIT_REF="${CHRONO_GIT_REF:-3eb56218b}"
THIRD_PARTY_CACHE_ROOT="${THIRD_PARTY_CACHE_ROOT:-${ROOT_DIR}/third_party/cache}"
CHRONO_CACHE_DIR="${CHRONO_CACHE_DIR:-${THIRD_PARTY_CACHE_ROOT}/chrono-cache}"
CHRONO_ARCHIVE_OUTPUT="${CHRONO_ARCHIVE_OUTPUT:-${THIRD_PARTY_CACHE_ROOT}/chrono-source.tar.gz}"

CMAKE_VERSION="${CMAKE_VERSION:-3.26.0}"
CMAKE_CACHE_DIR="${CMAKE_CACHE_DIR:-${ROOT_DIR}/docker/cuda-builder/deps/cmake-cache}"
CMAKE_ARCHIVE_OUTPUT="${CMAKE_ARCHIVE_OUTPUT:-${ROOT_DIR}/docker/cuda-builder/deps/cmake-${CMAKE_VERSION}-linux-x86_64.tar.gz}"
CMAKE_DOWNLOAD_URL="${CMAKE_DOWNLOAD_URL:-https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-linux-x86_64.tar.gz}"

EIGEN3_VERSION="${EIGEN3_VERSION:-3.4.0}"
EIGEN3_CACHE_DIR="${EIGEN3_CACHE_DIR:-${THIRD_PARTY_CACHE_ROOT}/eigen3-cache}"
EIGEN3_ARCHIVE_OUTPUT="${EIGEN3_ARCHIVE_OUTPUT:-${THIRD_PARTY_CACHE_ROOT}/eigen-${EIGEN3_VERSION}.tar.gz}"
EIGEN3_DOWNLOAD_URL="${EIGEN3_DOWNLOAD_URL:-https://gitlab.com/libeigen/eigen/-/archive/${EIGEN3_VERSION}/eigen-${EIGEN3_VERSION}.tar.gz}"

OPENMPI_VERSION="${OPENMPI_VERSION:-4.1.6}"
OPENMPI_CACHE_DIR="${OPENMPI_CACHE_DIR:-${THIRD_PARTY_CACHE_ROOT}/openmpi-cache}"
OPENMPI_ARCHIVE_OUTPUT="${OPENMPI_ARCHIVE_OUTPUT:-${THIRD_PARTY_CACHE_ROOT}/openmpi-${OPENMPI_VERSION}.tar.gz}"
OPENMPI_DOWNLOAD_URL="${OPENMPI_DOWNLOAD_URL:-https://download.open-mpi.org/release/open-mpi/v4.1/openmpi-${OPENMPI_VERSION}.tar.gz}"

HDF5_ARCHIVE_OUTPUT="${HDF5_ARCHIVE_OUTPUT:-${THIRD_PARTY_CACHE_ROOT}/CMake-hdf5-1.14.1-2.tar.gz}"
H5ENGINE_SPH_ARCHIVE_OUTPUT="${H5ENGINE_SPH_ARCHIVE_OUTPUT:-${THIRD_PARTY_CACHE_ROOT}/h5engine-sph.tar.gz}"
H5ENGINE_DEM_ARCHIVE_OUTPUT="${H5ENGINE_DEM_ARCHIVE_OUTPUT:-${THIRD_PARTY_CACHE_ROOT}/h5engine-dem.tar.gz}"

MUPARSERX_GIT_URL="${MUPARSERX_GIT_URL:-https://github.com/joe-cheung-cae/muparserx.git}"
MUPARSERX_GIT_BRANCH="${MUPARSERX_GIT_BRANCH:-master}"
MUPARSERX_CACHE_DIR="${MUPARSERX_CACHE_DIR:-${THIRD_PARTY_CACHE_ROOT}/muparserx-cache}"
MUPARSERX_ARCHIVE_OUTPUT="${MUPARSERX_ARCHIVE_OUTPUT:-${THIRD_PARTY_CACHE_ROOT}/muparserx-source.tar.gz}"

MSMPI_SDK_ARCHIVE_OUTPUT="${MSMPI_SDK_ARCHIVE_OUTPUT:-${THIRD_PARTY_CACHE_ROOT}/msmpi-sdk.zip}"
MSMPI_REDIST_ARCHIVE_OUTPUT="${MSMPI_REDIST_ARCHIVE_OUTPUT:-${THIRD_PARTY_CACHE_ROOT}/msmpi-redist.zip}"
MSMPI_SDK_URL="${MSMPI_SDK_URL:-}"
MSMPI_REDIST_URL="${MSMPI_REDIST_URL:-}"

usage() {
  cat <<'EOF'
Usage: scripts/prepare-third-party-cache.sh [--deps chrono,eigen3,openmpi,hdf5,h5engine,muparserx] [--force-refresh] [--offline-only]

Prepares local third-party source or release archives under third_party/cache/ for online or offline installs.
EOF
}

while [[ $# -gt 0 ]]; do
  case "${1}" in
    --deps)
      DEPS_CSV="${2:?Missing value for --deps}"
      shift 2
      ;;
    --force-refresh)
      FORCE_REFRESH=true
      shift
      ;;
    --offline-only)
      OFFLINE_ONLY=true
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

download_file() {
  local url="$1"
  local output="$2"

  mkdir -p "$(dirname "${output}")"
  if [[ -f "${output}" ]] && [[ "${FORCE_REFRESH}" != "true" ]]; then
    return 0
  fi
  if [[ -z "${url}" ]]; then
    echo "Missing download URL for ${output}" >&2
    exit 1
  fi
  if [[ "${OFFLINE_ONLY}" == "true" ]]; then
    if [[ ! -f "${output}" ]]; then
      echo "Offline-only mode requires a pre-populated archive: ${output}" >&2
      exit 1
    fi
    return 0
  fi
  curl -fsSL "${url}" -o "${output}"
}

prepare_git_archive() {
  local git_url="$1"
  local git_ref="$2"
  local cache_dir="$3"
  local output="$4"
  local marker_name="$5"

  local worktree_dir="${cache_dir}/worktree"
  local stage_dir
  stage_dir="$(mktemp -d)"

  if [[ "${FORCE_REFRESH}" == "true" ]]; then
    rm -rf "${worktree_dir}"
  fi

  mkdir -p "${cache_dir}" "$(dirname "${output}")"

  if [[ "${OFFLINE_ONLY}" == "true" ]] && [[ ! -f "${output}" ]]; then
    echo "Offline-only mode requires a pre-populated archive: ${output}" >&2
    exit 1
  fi

  if [[ ! -f "${output}" ]] || [[ "${FORCE_REFRESH}" == "true" ]]; then
    if [[ ! -d "${worktree_dir}/.git" ]]; then
      [[ "${OFFLINE_ONLY}" == "true" ]] && exit 1
      git clone "${git_url}" "${worktree_dir}"
    fi
    (
      cd "${worktree_dir}"
      if ! git fetch --depth 1 origin "${git_ref}"; then
        if ! git fetch origin "${git_ref}"; then
          git fetch origin --tags
        fi
      fi
      if git rev-parse --verify FETCH_HEAD >/dev/null 2>&1; then
        git checkout --force FETCH_HEAD
      else
        git checkout --force "${git_ref}"
      fi
    )
    rsync -a --delete --exclude='.git' --exclude='build' "${worktree_dir}/" "${stage_dir}/"
    printf '%s\n' "${git_ref}" > "${stage_dir}/${marker_name}"
    tar -czf "${output}" -C "${stage_dir}" .
  fi

  rm -rf "${stage_dir}"
}

ensure_local_archive() {
  local archive_path="$1"
  if [[ ! -f "${archive_path}" ]]; then
    echo "Expected archive to exist: ${archive_path}" >&2
    exit 1
  fi
}

prepare_cache_chrono() {
  prepare_git_archive "${CHRONO_GIT_URL}" "${CHRONO_GIT_REF}" "${CHRONO_CACHE_DIR}" "${CHRONO_ARCHIVE_OUTPUT}" ".chrono-source-ref"
}

prepare_cache_cmake() {
  mkdir -p "${CMAKE_CACHE_DIR}"
  download_file "${CMAKE_DOWNLOAD_URL}" "${CMAKE_ARCHIVE_OUTPUT}"
}

prepare_cache_eigen3() {
  mkdir -p "${EIGEN3_CACHE_DIR}"
  download_file "${EIGEN3_DOWNLOAD_URL}" "${EIGEN3_ARCHIVE_OUTPUT}"
}

prepare_cache_openmpi() {
  mkdir -p "${OPENMPI_CACHE_DIR}"
  download_file "${OPENMPI_DOWNLOAD_URL}" "${OPENMPI_ARCHIVE_OUTPUT}"
}

prepare_cache_hdf5() {
  if [[ -f "${HDF5_ARCHIVE_OUTPUT}" ]]; then
    return 0
  fi

  local builder_archive="${ROOT_DIR}/docker/cuda-builder/deps/CMake-hdf5-1.14.1-2.tar.gz"
  if [[ -f "${builder_archive}" ]]; then
    mkdir -p "$(dirname "${HDF5_ARCHIVE_OUTPUT}")"
    cp "${builder_archive}" "${HDF5_ARCHIVE_OUTPUT}"
    return 0
  fi

  ensure_local_archive "${HDF5_ARCHIVE_OUTPUT}"
}

prepare_cache_h5engine() {
  if [[ -f "${H5ENGINE_SPH_ARCHIVE_OUTPUT}" ]] && [[ -f "${H5ENGINE_DEM_ARCHIVE_OUTPUT}" ]]; then
    return 0
  fi

  local builder_root="${ROOT_DIR}/docker/cuda-builder/deps"
  if [[ ! -f "${H5ENGINE_SPH_ARCHIVE_OUTPUT}" ]] && [[ -f "${builder_root}/h5engine-sph.tar.gz" ]]; then
    mkdir -p "$(dirname "${H5ENGINE_SPH_ARCHIVE_OUTPUT}")"
    cp "${builder_root}/h5engine-sph.tar.gz" "${H5ENGINE_SPH_ARCHIVE_OUTPUT}"
  fi
  if [[ ! -f "${H5ENGINE_DEM_ARCHIVE_OUTPUT}" ]] && [[ -f "${builder_root}/h5engine-dem.tar.gz" ]]; then
    mkdir -p "$(dirname "${H5ENGINE_DEM_ARCHIVE_OUTPUT}")"
    cp "${builder_root}/h5engine-dem.tar.gz" "${H5ENGINE_DEM_ARCHIVE_OUTPUT}"
  fi

  ensure_local_archive "${H5ENGINE_SPH_ARCHIVE_OUTPUT}"
  ensure_local_archive "${H5ENGINE_DEM_ARCHIVE_OUTPUT}"
}

prepare_cache_muparserx() {
  prepare_git_archive "${MUPARSERX_GIT_URL}" "${MUPARSERX_GIT_BRANCH}" "${MUPARSERX_CACHE_DIR}" "${MUPARSERX_ARCHIVE_OUTPUT}" ".muparserx-source-ref"
}

RESOLVED_DEPS_CSV="$(third_party_resolve_dep_order "${DEPS_CSV}" linux)"
IFS=',' read -r -a DEPS <<< "${RESOLVED_DEPS_CSV}"

prepare_cache_cmake

for dep in "${DEPS[@]}"; do
  cache_handler="$(third_party_cache_command "${dep}")"
  "${cache_handler}"
done

if [[ -n "${MSMPI_SDK_URL}" ]]; then
  download_file "${MSMPI_SDK_URL}" "${MSMPI_SDK_ARCHIVE_OUTPUT}"
fi
if [[ -n "${MSMPI_REDIST_URL}" ]]; then
  download_file "${MSMPI_REDIST_URL}" "${MSMPI_REDIST_ARCHIVE_OUTPUT}"
fi

printf 'Prepared third-party archives: cmake,%s\n' "$(IFS=,; printf '%s' "${DEPS[*]}")"
