# CUDA Builder Images

This repository contains CUDA builder images plus the scripts and docs used to build and exchange source-build capable offline environments.

## Keeps

- `docker/cuda-builder/`
- `scripts/build-builder-image.sh`
- `scripts/install-offline-tools.sh`
- `scripts/export/images.sh`
- `scripts/import/images.sh`
- `scripts/common/*.sh`
- `tests/*.sh`
- `.env.example`
- `docs/platform-contract.md`
- `docs/ubuntu20-rootless-docker-compose-nvidia-offline-guide.md`

## Build and Exchange

```bash
cp .env.example .env
scripts/build-builder-image.sh
scripts/build-builder-image.sh --platform ubuntu2204
scripts/build-builder-image.sh --platform ubuntu2404
scripts/build-builder-image.sh --all-platforms
scripts/build-builder-image.sh --platform ubuntu2204
scripts/build-builder-image.sh --all-platforms
scripts/build-builder-image.sh --all-platforms --cuda-version 12.4.1
scripts/export/images.sh
scripts/export/images.sh --output artifacts/offline-images-cuda12-matrix.tar.gz
scripts/export/images.sh --cuda-version 12.4.1 --output artifacts/offline-images-cuda12.4.1.tar.gz
scripts/export/images.sh --platform centos7
scripts/export/images.sh --platform rocky9
scripts/import/images.sh --input artifacts/offline-images.tar.gz
scripts/install-offline-tools.sh --prefix /opt/gpu-devops
/opt/gpu-devops/bin/build-builder-image.sh --platform ubuntu2204
/opt/gpu-devops/bin/export-images.sh
/opt/gpu-devops/bin/export-images.sh --output artifacts/offline-images-cuda12-matrix.tar.gz
/opt/gpu-devops/bin/export-images.sh --cuda-version 12.4.1 --output artifacts/offline-images-cuda12.4.1.tar.gz
/opt/gpu-devops/bin/export-images.sh --platform ubuntu2404
/opt/gpu-devops/bin/import-images.sh --input artifacts/offline-images.tar.gz
```

The default `.env.example` targets the latest available CUDA `12.x` tag for each supported platform.
`centos7` is pinned to `12.4.0`, while `rocky8`, `rocky9`, `ubuntu2204`, and `ubuntu2404` default to `12.9.1`.
Set `BUILDER_CUDA_VERSION` in `.env` to change the shared fallback version, or set `BUILDER_PLATFORM_CUDA_VERSIONS` to pin specific platforms.
Use `scripts/build-builder-image.sh --all-platforms` before exporting the mixed-version full offline bundle.
Image tags now use the rule `tf-particles/devops/cuda-builder:${platform}-${BUILDER_CUDA_VERSION}`.
The default platform in `.env.example` is `ubuntu2404`, while `centos7` remains available as a compatibility image.
Use `scripts/export/images.sh --platform <name>` to export one builder platform instead of the full matrix.
Use `scripts/export/images.sh --cuda-version <version>` to export a version-specific full matrix without editing `.env`.
The builder baseline includes CUDA/C++, CMake, Conan/Ninja, and autotools-class source-build tooling for upstream projects such as Open MPI, HDF5, NCCL, and AMGX.

The offline installer copies the minimal runtime tree into the requested prefix:
- `bin/` wrapper commands
- `scripts/` helper and entrypoint scripts
- `docker/` builder Dockerfiles
- `third_party/cache/` vendored CMake archive
- `.env` and `.env.example`
- `README.md` and `docs/`

The Docker build context includes `third_party/cache/cmake-3.26.0-linux-x86_64.tar.gz`.

- [docs/platform-contract.md](docs/platform-contract.md)
- [docs/ubuntu20-rootless-docker-compose-nvidia-offline-guide.md](docs/ubuntu20-rootless-docker-compose-nvidia-offline-guide.md)
