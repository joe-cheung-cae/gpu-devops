# CUDA Builder Images

This repository keeps the CUDA/CMake builder image definitions and the minimal scripts and docs needed to build them.

## What is kept

- Builder Dockerfiles under `docker/cuda-builder/`
- The image build entrypoint `scripts/build-builder-image.sh`
- Shared progress helpers in `scripts/common/progress.sh`
- The build image test in `tests/build-builder-image-test.sh`
- The image configuration example in `.env.example`
- The builder image contract in `docs/platform-contract.md`

## Supported images

- Base family: `tf-particles/devops/cuda-builder:cuda11.7-cmake3.26`
- Platforms: `centos7`, `rocky8`, `ubuntu2204`

The builder images keep a common CUDA/C++ toolchain baseline. They do not bundle project-specific third-party dependencies.

## Build

```bash
cp .env.example .env
scripts/build-builder-image.sh
scripts/build-builder-image.sh --platform ubuntu2204
scripts/build-builder-image.sh --all-platforms
```

The Docker build context includes the vendored CMake archive at `third_party/cache/cmake-3.26.0-linux-x86_64.tar.gz`.

## Image Export / Import

Export the builder images into a compressed bundle:

```bash
scripts/export/images.sh
scripts/export/images.sh --only-build-images
scripts/export/images.sh --only-build-images --platform centos7
```

Import a previously exported bundle:

```bash
scripts/import/images.sh --input artifacts/offline-images.tar.gz
```

The export command writes:

- `<archive>.tar.gz`
- `<archive>.tar.gz.images.txt`
- `<archive>.tar.gz.sha256`

## Reference

- [docs/platform-contract.md](docs/platform-contract.md)
- [docs/ubuntu20-rootless-docker-compose-nvidia-offline-guide.md](docs/ubuntu20-rootless-docker-compose-nvidia-offline-guide.md)
