# Shared GitLab GPU Build Platform

This repository provides a shared CUDA/CMake build platform plus a shell-runner workflow for GitLab jobs. It keeps the project build path, offline image export/import, and portable bundle tooling. It also delivers a project-local `third_party` tree for target repositories. It does not provide a Docker-based GitLab Runner deployment anymore.

## What it ships

- A standard CUDA builder image family for project jobs
- Builder platform variants: `centos7`, `rocky8`, `ubuntu2204`
- A local CUDA/C++ Compose workflow for one or more builder platforms
- A project-local `third_party` delivery flow for dependency tarballs and install recipes
- A shell-runner registration path for hosts that run jobs as the Linux user `gitlab-runner`
- Image export/import and portable project bundle tooling
- Example GitLab CI and a minimal CUDA/CMake smoke project

The builder images keep only the common CUDA/C++ toolchain baseline:

- CUDA compiler, CMake, Conan, Ninja, UUID development headers, and `ccache`
- project dependencies such as Chrono, Eigen3, OpenMPI, HDF5, h5engine, and muparserx are prepared later into `third_party/<platform>`

## Tutorials

- English guide: [docs/tutorial.en.md](docs/tutorial.en.md)
- Chinese guide: [docs/tutorial.zh-CN.md](docs/tutorial.zh-CN.md)
- Usage guide: [docs/usage.en.md](docs/usage.en.md)
- 中文使用指南: [docs/usage.zh-CN.md](docs/usage.zh-CN.md)

## Platform contract

- Projects consume the published builder image directly from `.gitlab-ci.yml` or the shell-runner example
- The platform guarantees a standard CUDA/CMake toolchain baseline, while project-specific dependencies live in the delivered `third_party` tree
- The target project repository owns its own `third_party` submodule or snapshot; this repository only delivers the content

## Directory layout

- `docker/cuda-builder/`: standard CUDA builder image and dependency installers used to prepare project `third_party` content
- `runner/`: shell-runner registration script
- `scripts/`: operator scripts for setup, image build, and verification
- `examples/`: example GitLab CI config and CUDA/CMake smoke test
- `docs/`: operator and platform documentation

## Prerequisites

- Docker Engine 24+
- Docker Compose plugin or standalone `docker-compose`
- NVIDIA driver installed on the host
- NVIDIA Container Toolkit configured for Docker
- A GitLab instance and a Runner registration token

## Quick start

1. Copy [.env.example](.env.example) to `.env` and fill in GitLab values.
2. Run `scripts/verify-host.sh` to validate the host.
3. Build and publish the shared builder image with `scripts/build-builder-image.sh --all-platforms`.
4. If the target host is air-gapped, export the deployment images with `scripts/export/images.sh`.
5. Prepare or refresh the project-local `third_party` tree with `scripts/prepare-builder-deps.sh --platform centos7` or `scripts/install-third-party.sh --host linux --platform centos7`.
6. Register the shell runner with `runner/register-shell-runner.sh gpu`.
7. Validate the deployment with [docs/self-check.md](docs/self-check.md).

## Compose files

- [docker-compose.yml](docker-compose.yml): local CUDA/C++ project build and project `third_party` consumption
- [compose.sh](scripts/compose.sh) targets `docker-compose.yml`

Project build containers started through `scripts/compose.sh` run as the current host caller UID/GID by default. This does not change the Docker daemon itself into rootless mode. On Linux, the project-side Docker entrypoints still expect rootless-style container access by default. Set `CUDA_CXX_ALLOW_ROOTFUL_DOCKER=1` only when you need to keep a legacy rootful host temporarily.

Before using `.gpu-devops/scripts/compose.sh` or `.gpu-devops/scripts/prepare-builder-deps.sh` on the offline host, finish the rootless Docker setup described in [docs/offline-env-configuration.md](docs/offline-env-configuration.md). The imported bundle writes project assets under `.gpu-devops/`, including `.gpu-devops/third_party/`.

Local project build examples:

- Single platform: `scripts/compose.sh run --rm cuda-cxx-centos7`
- Multiple platforms: `scripts/compose.sh up --abort-on-container-exit cuda-cxx-centos7 cuda-cxx-ubuntu2204`
- Profile-based selection: `docker compose --profile centos7 --profile rocky8 -f docker-compose.yml up`

The build Compose file mounts the current host working tree into `/workspace`. `CUDA_CXX_PROJECT_DIR` is then resolved inside that workspace, build output is written to `CUDA_CXX_BUILD_ROOT/<platform>`, install output is written to `CUDA_CXX_INSTALL_ROOT/<platform>`, and project dependencies are resolved from `CUDA_CXX_THIRD_PARTY_ROOT/<platform>`.

For a ready-made `.env` example with custom `CUDA_CXX_CMAKE_ARGS` and `CUDA_CXX_BUILD_ARGS`, see [cuda-cxx.env.example](examples/env/cuda-cxx.env.example).

## Shell runner path

The shell-runner path runs GitLab jobs as the Linux user `gitlab-runner` and calls `.gpu-devops/scripts/compose.sh run --rm cuda-cxx-centos7` instead of using GitLab's Docker executor.

Use the shell-runner registration script:

```bash
runner/register-shell-runner.sh gpu
runner/register-shell-runner.sh multi
```

For a ready-made CI example, start from [examples/gitlab-ci/shared-gpu-shell-runner.yml](examples/gitlab-ci/shared-gpu-shell-runner.yml).

The tag policy is:

- `gpu`: default shared GPU jobs
- `cuda`: jobs that require the standard CUDA toolchain
- `gpu-multi`: jobs that need the multi-GPU runner pool
- `cuda-11`: jobs pinned to the CUDA 11.7 platform baseline

## Builder images

The builder image family is:

`tf-particles/devops/cuda-builder:cuda11.7-cmake3.26`

The default supported tags are:

- `tf-particles/devops/cuda-builder:cuda11.7-cmake3.26-centos7`
- `tf-particles/devops/cuda-builder:cuda11.7-cmake3.26-rocky8`
- `tf-particles/devops/cuda-builder:cuda11.7-cmake3.26-ubuntu2204`

Projects should pin to a published immutable tag rather than `latest`.

All three builder Dockerfiles accept the same proxy build arguments from `scripts/build-builder-image.sh`.

If you rebuild builder images or prepare offline dependency media frequently, pre-stage the third-party archives on the host:

```bash
scripts/prepare-third-party-cache.sh
```

Heavy project dependencies are no longer baked into the base builder image. `Eigen3` and `OpenMPI` now follow the same project-local install path as Chrono, HDF5, h5engine, and muparserx:

```bash
scripts/prepare-builder-deps.sh --platform centos7
scripts/install-third-party.sh --host linux --platform centos7
scripts/install-third-party.sh --host windows
```

The third-party entrypoints resolve dependencies from a shared registry. `--deps` selects the target packages, and the scripts automatically add required upstream packages and run them in dependency order. The resulting install trees are delivered into the project-local `third_party` directory instead of a base-image cache.

## Offline image bundle

For air-gapped deployment, `scripts/export/images.sh` writes a compressed archive containing the builder tags derived from `BUILDER_IMAGE_FAMILY` and `BUILDER_PLATFORMS`. It also writes a sibling SHA256 file at `<archive>.sha256`. Copy both files to the target host and load the archive with `scripts/import/images.sh`.

If you only need part of that image set, you can export a smaller archive:

```bash
scripts/export/images.sh --only-build-images --output artifacts/offline-build-images.tar.gz
scripts/export/images.sh --only-build-images --platform centos7 --output artifacts/offline-build-images-centos7.tar.gz
```

The image-only scripts and the project bundle scripts share the same underlying image export/import implementation, so the difference between them is output format and installed assets, not a separate Docker save/load path.

## Project integration bundle

Use the project bundle scripts when another project lives outside this repository and still needs exported images, ready-to-use integration assets, or both:

- `scripts/export/project-bundle.sh`
- `scripts/import/project-bundle.sh --target-dir /path/to/other/project`

The bundle scripts support three modes:

- `--mode all`: export/import images and assets together
- `--mode images`: export/import images only
- `--mode assets`: export/import files only

If you receive the portable toolkit as an archive, unpack it first:

```bash
tar -xzf artifacts/project-operator-toolkit.tar.gz
.gpu-devops/scripts/import/images.sh --input /path/to/offline-images.tar.gz
.gpu-devops/scripts/prepare-builder-deps.sh --platform centos7
.gpu-devops/scripts/install-third-party.sh --host linux --platform centos7
```

The imported `.gpu-devops/` directory is a functional operator toolkit. It includes:

- image import/export scripts
- builder image build scripts plus `docker/cuda-builder/`
- shell-runner registration assets under `runner/`
- the existing Compose wrappers and docs
- delivered project `third_party` content ready for the target repository to consume

When the target project repository receives the delivered assets, it owns the `third_party` submodule or snapshot in its own tree. This repository only ships the content that can be placed under `third_party/`.
## Project usage

See [examples/gitlab-ci/shared-gpu-shell-runner.yml](examples/gitlab-ci/shared-gpu-shell-runner.yml) for a complete example.

Additional reference docs:

- [docs/operations.md](docs/operations.md)
- [docs/self-check.md](docs/self-check.md)
- [docs/platform-contract.md](docs/platform-contract.md)
- [docs/offline-env-configuration.md](docs/offline-env-configuration.md)

## Limitations

- No Kubernetes deployment in v1
- No autoscaling in v1
- No support for multiple CUDA major versions in v1
- Multi-GPU scheduling is implemented as a dedicated Runner pool, not fine-grained per-job GPU reservation
