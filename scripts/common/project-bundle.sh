#!/usr/bin/env bash

if [[ -n "${SCRIPT_COMMON_PROJECT_BUNDLE_LOADED:-}" ]]; then
  return 0
fi
SCRIPT_COMMON_PROJECT_BUNDLE_LOADED=1

project_bundle_assets() {
  cat <<'EOF'
.env.example
docker-compose.yml
examples/gitlab-ci/shared-gpu-shell-runner.yml
runner/register-shell-runner.sh
third_party
docker/cuda-builder
scripts/build-builder-image.sh
scripts/common
scripts/common/docker-rootless-common.sh
scripts/compose.sh
scripts/export
scripts/export/images.sh
scripts/export/project-bundle.sh
scripts/prepare-builder-deps.sh
scripts/import
scripts/import/images.sh
scripts/import/project-bundle.sh
scripts/install-third-party.sh
scripts/prepare-third-party-cache.sh
scripts/verify-host.sh
docs/operations.md
docs/offline-env-configuration.md
docs/ubuntu20-rootless-docker-compose-nvidia-offline-guide.md
docs/tutorial.en.md
docs/tutorial.zh-CN.md
EOF
}

normalize_bundle_mode() {
  local mode="${1:-all}"

  case "${mode}" in
    all)
      printf 'all\n'
      ;;
    images|image)
      printf 'images\n'
      ;;
    assets|asset|files|file)
      printf 'assets\n'
      ;;
    *)
      echo "Unsupported bundle mode: ${mode}" >&2
      echo "Expected one of: all, images, assets" >&2
      exit 1
      ;;
  esac
}

write_imported_project_env() {
  local env_path="$1"
  local target_dir="$2"
  local assets_subdir="$3"

  {
    printf 'HOST_PROJECT_DIR=%q\n' "${target_dir}"
    printf 'CUDA_CXX_PROJECT_DIR=.\n'
    printf 'CUDA_CXX_BUILD_ROOT=%q\n' "${assets_subdir}/artifacts/cuda-cxx-build"
    printf 'CUDA_CXX_INSTALL_ROOT=%q\n' "${assets_subdir}/artifacts/cuda-cxx-install"
    printf 'CUDA_CXX_THIRD_PARTY_ROOT=%q\n' "${assets_subdir}/third_party"
    printf 'CUDA_CXX_CMAKE_GENERATOR=Ninja\n'
    printf 'CUDA_CXX_CMAKE_ARGS=\n'
    printf 'CUDA_CXX_BUILD_ARGS=\n'
  } > "${env_path}"
}
