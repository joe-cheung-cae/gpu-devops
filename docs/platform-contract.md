# Platform Contract

## Builder family

- Builder image family defaults to `tf-particles/devops/cuda-builder`
- The default CUDA version is `11.7.1`
- Supported platform keys:
  - `centos7` -> `nvidia/cuda:${BUILDER_CUDA_VERSION}-devel-centos7`
  - `rocky8` -> `nvidia/cuda:${BUILDER_CUDA_VERSION}-devel-rockylinux8`
  - `rocky9` -> `nvidia/cuda:${BUILDER_CUDA_VERSION}-devel-rockylinux9`
  - `ubuntu2204` -> `nvidia/cuda:${BUILDER_CUDA_VERSION}-devel-ubuntu22.04`
  - `ubuntu2404` -> `nvidia/cuda:${BUILDER_CUDA_VERSION}-devel-ubuntu24.04`
- The public image tags are derived as `${BUILDER_IMAGE_FAMILY}:${platform}-${BUILDER_CUDA_VERSION}`
- Default platform: `ubuntu2404`
- Example tag: `tf-particles/devops/cuda-builder:ubuntu2404-11.7.1`

## Baseline

- All builder images provide a common CUDA/C++ toolchain baseline
- The baseline includes `cmake`, `conan`, `ninja`, `ccache`, `git`, `gdb`, `python3`, compilers, and UUID development headers
- The images do not bundle project-specific third-party dependencies

## Vendored build asset

- `third_party/cache/cmake-3.26.0-linux-x86_64.tar.gz` is copied into each image and unpacked into `/usr/local`
- The Dockerfiles should continue to reference that archive directly from the build context

## Image exchange

- `scripts/export/images.sh` exports the configured builder images into a compressed archive
- `scripts/export/images.sh --platform <name>` exports one configured builder platform into a compressed archive
- `scripts/import/images.sh` loads a previously exported archive into the local Docker daemon

## Offline install layout

- `scripts/install-offline-tools.sh --prefix /opt/gpu-devops` installs a self-contained tree
- The installed tree includes:
  - `bin/` wrapper commands
  - `scripts/` entrypoints and shared helpers
  - `docker/cuda-builder/` Dockerfiles
  - `third_party/cache/cmake-3.26.0-linux-x86_64.tar.gz`
  - `.env` and `.env.example`
- `README.md` and `docs/`
- Installed commands resolve their defaults from the prefix tree, not the source checkout
