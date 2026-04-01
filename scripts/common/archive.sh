#!/usr/bin/env bash

if [[ -n "${SCRIPT_COMMON_ARCHIVE_LOADED:-}" ]]; then
  return 0
fi
SCRIPT_COMMON_ARCHIVE_LOADED=1

export_images_archive() {
  local archive_path="$1"
  shift
  local images=("$@")

  mkdir -p "$(dirname "${archive_path}")"
  docker save "${images[@]}" | gzip -c > "${archive_path}"
  printf '%s\n' "${images[@]}" > "${archive_path}.images.txt"
  write_bundle_sha256 "${archive_path}"
}

import_image_archive() {
  local archive_path="$1"
  local skip_hash_check="${2:-false}"

  if [[ ! -f "${archive_path}" ]]; then
    echo "Image archive not found: ${archive_path}" >&2
    exit 1
  fi

  if [[ "${skip_hash_check}" != "true" ]]; then
    verify_bundle_sha256 "${archive_path}"
  fi

  if [[ "${archive_path}" == *.gz ]]; then
    gzip -dc "${archive_path}" | docker load
  else
    docker load -i "${archive_path}"
  fi
}

bundle_sha256_path() {
  local archive_path="$1"
  printf '%s.sha256\n' "${archive_path}"
}

bundle_sha256_tool() {
  if command -v sha256sum >/dev/null 2>&1; then
    printf 'sha256sum\n'
    return 0
  fi

  if command -v shasum >/dev/null 2>&1; then
    printf 'shasum\n'
    return 0
  fi

  if command -v openssl >/dev/null 2>&1; then
    printf 'openssl\n'
    return 0
  fi

  echo "No SHA256 tool available. Install sha256sum, shasum, or openssl." >&2
  exit 1
}

compute_bundle_sha256() {
  local archive_path="$1"
  local tool
  tool="$(bundle_sha256_tool)"

  case "${tool}" in
    sha256sum)
      sha256sum "${archive_path}" | awk '{print $1}'
      ;;
    shasum)
      shasum -a 256 "${archive_path}" | awk '{print $1}'
      ;;
    openssl)
      openssl dgst -sha256 -r "${archive_path}" | awk '{print $1}'
      ;;
  esac
}

write_bundle_sha256() {
  local archive_path="$1"
  local hash_path
  local checksum

  checksum="$(compute_bundle_sha256 "${archive_path}")"
  hash_path="$(bundle_sha256_path "${archive_path}")"
  printf '%s  %s\n' "${checksum}" "$(basename "${archive_path}")" > "${hash_path}"
}

verify_bundle_sha256() {
  local archive_path="$1"
  local hash_path
  local expected
  local actual

  hash_path="$(bundle_sha256_path "${archive_path}")"

  if [[ ! -f "${hash_path}" ]]; then
    echo "SHA256 file not found: ${hash_path}" >&2
    exit 1
  fi

  expected="$(awk 'NR==1 {print $1}' "${hash_path}")"
  actual="$(compute_bundle_sha256 "${archive_path}")"

  if [[ -z "${expected}" || "${expected}" != "${actual}" ]]; then
    echo "SHA256 verification failed for ${archive_path}" >&2
    echo "Expected: ${expected:-<missing>}" >&2
    echo "Actual:   ${actual}" >&2
    exit 1
  fi
}
