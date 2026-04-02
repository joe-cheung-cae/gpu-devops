#!/usr/bin/env bash
set -euo pipefail

third_party_all_deps_csv() {
  printf '%s\n' 'chrono,eigen3,openmpi,hdf5,h5engine,muparserx'
}

third_party_validate_dep() {
  case "$1" in
    chrono|eigen3|openmpi|hdf5|h5engine|muparserx)
      ;;
    *)
      echo "Unsupported dependency: $1" >&2
      echo "Expected one of: $(third_party_all_deps_csv)" >&2
      return 1
      ;;
  esac
}

third_party_dep_direct_deps() {
  case "$1" in
    h5engine)
      printf '%s\n' 'hdf5'
      ;;
    *)
      printf '\n'
      ;;
  esac
}

third_party_dep_supported_hosts() {
  case "$1" in
    chrono|eigen3|openmpi|hdf5|muparserx)
      printf '%s\n' 'linux,windows'
      ;;
    h5engine)
      printf '%s\n' 'linux'
      ;;
  esac
}

third_party_require_host_support() {
  local dep="$1"
  local host="$2"
  local supported
  supported="$(third_party_dep_supported_hosts "${dep}")"
  case ",${supported}," in
    *,"${host}",*)
      ;;
    *)
      echo "Dependency '${dep}' does not support host '${host}'" >&2
      return 1
      ;;
  esac
}

declare -Ag THIRD_PARTY_REGISTRY_CLOSURE=()
declare -Ag THIRD_PARTY_REGISTRY_VISITING=()

third_party__resolve_closure() {
  local dep="$1"
  local host="$2"
  local deps_csv child

  third_party_validate_dep "${dep}" || return 1
  third_party_require_host_support "${dep}" "${host}" || return 1

  if [[ -n "${THIRD_PARTY_REGISTRY_CLOSURE[${dep}]:-}" ]]; then
    return 0
  fi
  if [[ -n "${THIRD_PARTY_REGISTRY_VISITING[${dep}]:-}" ]]; then
    echo "Circular third-party dependency detected at '${dep}'" >&2
    return 1
  fi

  THIRD_PARTY_REGISTRY_VISITING["${dep}"]=1
  deps_csv="$(third_party_dep_direct_deps "${dep}")"
  if [[ -n "${deps_csv}" ]]; then
    IFS=',' read -r -a _tp_children <<< "${deps_csv}"
    for child in "${_tp_children[@]}"; do
      [[ -n "${child}" ]] || continue
      third_party__resolve_closure "${child}" "${host}" || return 1
    done
  fi
  unset 'THIRD_PARTY_REGISTRY_VISITING['"${dep}"']'
  THIRD_PARTY_REGISTRY_CLOSURE["${dep}"]=1
}

third_party_resolve_dep_order() {
  local deps_csv="$1"
  local host="$2"
  local dep
  local requested=()
  local ordered=()
  local all_deps

  THIRD_PARTY_REGISTRY_CLOSURE=()
  THIRD_PARTY_REGISTRY_VISITING=()

  if [[ -z "${deps_csv}" ]]; then
    deps_csv="$(third_party_all_deps_csv)"
  fi

  IFS=',' read -r -a requested <<< "${deps_csv}"
  for dep in "${requested[@]}"; do
    dep="${dep//[[:space:]]/}"
    [[ -n "${dep}" ]] || continue
    third_party__resolve_closure "${dep}" "${host}" || return 1
  done

  all_deps="$(third_party_all_deps_csv)"
  IFS=',' read -r -a requested <<< "${all_deps}"
  for dep in "${requested[@]}"; do
    if [[ -n "${THIRD_PARTY_REGISTRY_CLOSURE[${dep}]:-}" ]]; then
      ordered+=("${dep}")
    fi
  done

  (IFS=,; printf '%s\n' "${ordered[*]}")
}

third_party_cache_command() {
  case "$1" in
    chrono)
      printf '%s\n' 'prepare_cache_chrono'
      ;;
    eigen3)
      printf '%s\n' 'prepare_cache_eigen3'
      ;;
    openmpi)
      printf '%s\n' 'prepare_cache_openmpi'
      ;;
    hdf5)
      printf '%s\n' 'prepare_cache_hdf5'
      ;;
    h5engine)
      printf '%s\n' 'prepare_cache_h5engine'
      ;;
    muparserx)
      printf '%s\n' 'prepare_cache_muparserx'
      ;;
  esac
}

third_party_linux_install_command() {
  local dep="$1"
  local deps_root="$2"
  local cache_root="$3"
  case "${dep}" in
    chrono)
      printf "DEPS_ROOT='%s' CHRONO_ARCHIVE='%s/chrono-source.tar.gz' /bin/bash '/toolkit/docker/cuda-builder/install-chrono.sh'\n" "${deps_root}" "${cache_root}"
      ;;
    eigen3)
      printf "DEPS_ROOT='%s' EIGEN3_ARCHIVE='%s/eigen-3.4.0.tar.gz' /bin/bash '/toolkit/docker/cuda-builder/install-eigen3.sh'\n" "${deps_root}" "${cache_root}"
      ;;
    openmpi)
      printf "DEPS_ROOT='%s' OPENMPI_ARCHIVE='%s/openmpi-4.1.6.tar.gz' /bin/bash '/toolkit/docker/cuda-builder/install-openmpi.sh'\n" "${deps_root}" "${cache_root}"
      ;;
    hdf5)
      printf "DEPS_ROOT='%s' HDF5_ARCHIVE='%s/CMake-hdf5-1.14.1-2.tar.gz' /bin/bash '/toolkit/docker/cuda-builder/install-hdf5.sh'\n" "${deps_root}" "${cache_root}"
      ;;
    h5engine)
      printf "DEPS_ROOT='%s' HDF5_INSTALL_PREFIX='%s/hdf5-install' H5ENGINE_SPH_ARCHIVE='%s/h5engine-sph.tar.gz' H5ENGINE_DEM_ARCHIVE='%s/h5engine-dem.tar.gz' /bin/bash '/toolkit/docker/cuda-builder/install-h5engine.sh'\n" "${deps_root}" "${deps_root}" "${cache_root}" "${cache_root}"
      ;;
    muparserx)
      printf "DEPS_ROOT='%s' MUPARSERX_ARCHIVE='%s/muparserx-source.tar.gz' /bin/bash '/toolkit/docker/cuda-builder/install-muparserx.sh'\n" "${deps_root}" "${cache_root}"
      ;;
  esac
}

third_party_windows_install_function() {
  case "$1" in
    chrono)
      printf '%s\n' 'install_windows_chrono'
      ;;
    eigen3)
      printf '%s\n' 'install_windows_eigen3'
      ;;
    openmpi)
      printf '%s\n' 'install_windows_msmpi'
      ;;
    hdf5)
      printf '%s\n' 'install_windows_hdf5'
      ;;
    h5engine)
      printf '%s\n' 'install_windows_h5engine'
      ;;
    muparserx)
      printf '%s\n' 'install_windows_muparserx'
      ;;
  esac
}
