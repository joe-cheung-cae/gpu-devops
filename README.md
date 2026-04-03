# CUDA Builder Images

This repository contains the CUDA/CMake builder images plus the minimal scripts and docs used to build and exchange them.

## Keeps

- `docker/cuda-builder/`
- `scripts/build-builder-image.sh`
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
scripts/build-builder-image.sh --all-platforms
scripts/build-builder-image.sh --platform ubuntu2204 --cuda-version 12.4.1
scripts/export/images.sh
scripts/export/images.sh --only-build-images
scripts/export/images.sh --only-build-images --platform centos7
scripts/import/images.sh --input artifacts/offline-images.tar.gz
```

Set `BUILDER_CUDA_VERSION` in `.env` to change the default CUDA version without passing `--cuda-version` on every build.

The Docker build context includes `third_party/cache/cmake-3.26.0-linux-x86_64.tar.gz`.

Image tags include the CUDA patch version, for example `cuda11.7.1-cmake3.26-centos7`.

- [docs/platform-contract.md](docs/platform-contract.md)
- [docs/ubuntu20-rootless-docker-compose-nvidia-offline-guide.md](docs/ubuntu20-rootless-docker-compose-nvidia-offline-guide.md)
