# Platform Contract

## Builder family

- Builder image family: `cuda11.7-cmake3.26`
- Supported platform keys:
  - `centos7` -> `nvidia/cuda:11.7.1-devel-centos7`
  - `rocky8` -> `nvidia/cuda:11.7.1-devel-rockylinux8`
  - `ubuntu2204` -> `nvidia/cuda:11.7.1-devel-ubuntu22.04`
- The public image tags are derived as `${BUILDER_IMAGE_FAMILY}-${platform}`

## Baseline

- All builder images provide a common CUDA/C++ toolchain baseline
- The baseline includes `cmake`, `conan`, `ninja`, `ccache`, `git`, `gdb`, `python3`, compilers, and UUID development headers
- The images do not bundle project-specific third-party dependencies

## Vendored build asset

- `third_party/cache/cmake-3.26.0-linux-x86_64.tar.gz` is copied into each image and unpacked into `/usr/local`
- The Dockerfiles should continue to reference that archive directly from the build context

## Image exchange

- `scripts/export/images.sh` exports the configured builder images into a compressed archive
- `scripts/import/images.sh` loads a previously exported archive into the local Docker daemon
- `--only-build-images` limits export to the builder image matrix
