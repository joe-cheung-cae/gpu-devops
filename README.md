# CUDA Builder Images

This repository contains the CUDA/CMake builder images plus the minimal scripts and docs used to build and exchange them.

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
scripts/build-builder-image.sh --all-platforms
scripts/build-builder-image.sh --platform ubuntu2204 --cuda-version 12.4.1
scripts/export/images.sh
scripts/export/images.sh --platform centos7
scripts/import/images.sh --input artifacts/offline-images.tar.gz
scripts/install-offline-tools.sh --prefix /opt/gpu-devops
/opt/gpu-devops/bin/build-builder-image.sh --platform ubuntu2204
/opt/gpu-devops/bin/export-images.sh
/opt/gpu-devops/bin/import-images.sh --input artifacts/offline-images.tar.gz
```

Set `BUILDER_CUDA_VERSION` in `.env` to change the default CUDA version without passing `--cuda-version` on every build.
Image tags now use the rule `tf-particles/devops/cuda-builder:${platform}-${BUILDER_CUDA_VERSION}`.

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
