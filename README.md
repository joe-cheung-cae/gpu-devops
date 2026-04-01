# Shared GitLab GPU Runner Platform

This repository provides a shared GitLab CI/CD platform for CUDA and CMake based projects. It ships:

- A standard CUDA builder image for project jobs
- Multiple builder platform variants: `centos7`, `rocky8`, `ubuntu2204`
- A Docker Compose based GitLab Runner deployment for GPU workloads
- An optional shell-runner path for hosts that run jobs as the Linux user `gitlab-runner`
- A Docker Compose based local CUDA/C++ build workflow for one or more builder platforms
- Registration and verification scripts
- Example GitLab CI and a minimal CUDA/CMake smoke project

The first release targets a single host with NVIDIA GPUs and shared Runner usage across multiple projects.

The shared builder images now keep only the common CUDA/C++ toolchain baseline:

- OpenMPI, Eigen3, CMake, Conan, Ninja, UUID development headers, and `ccache`
- a smaller base image that is faster to rebuild and export
- heavy project dependencies such as Chrono, HDF5, h5engine, and muparserx are prepared later into a project-local cache under `CUDA_CXX_DEPS_ROOT/<platform>`

## Tutorials

- Chinese guide: [docs/tutorial.zh-CN.md](/home/joe/repo/gpu-devops/docs/tutorial.zh-CN.md)
- English guide: [docs/tutorial.en.md](/home/joe/repo/gpu-devops/docs/tutorial.en.md)
- Step-by-step usage guide: [docs/usage.en.md](/home/joe/repo/gpu-devops/docs/usage.en.md)
- 中文步骤指南: [docs/usage.zh-CN.md](/home/joe/repo/gpu-devops/docs/usage.zh-CN.md)

## Platform contract

- Projects consume the published builder image directly from `.gitlab-ci.yml`
- Projects select shared GPU capacity through Runner tags
- The platform guarantees a standard CUDA/CMake toolchain baseline, not project-specific dependencies

## Directory layout

- `docker/cuda-builder/`: standard CUDA builder image
- `runner/`: Runner config templates and registration assets
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

1. Copy [.env.example](/home/joe/repo/gpu-devops/.env.example) to `.env` and fill in GitLab values.
2. Run `scripts/verify-host.sh` to validate the host.
3. Build and publish the shared builder image with `scripts/build-builder-image.sh`.
   Optional dependency cache staging: `scripts/prepare-third-party-cache.sh`
   Single platform: `scripts/build-builder-image.sh --platform ubuntu2204`
   All supported platforms: `scripts/build-builder-image.sh --all-platforms`
4. Prepare the Runner service image with `scripts/prepare-runner-service-image.sh`.
5. If the target host is air-gapped, export the deployment images with `scripts/export-images.sh`.
6. Start the Runner service with `scripts/runner-compose.sh up -d`.
7. Register Runner entries with `runner/register-runner.sh` for Docker executor, or `runner/register-shell-runner.sh` for a shell runner that invokes `docker compose`.
8. Validate the deployment with `docs/self-check.md`.

## Compose files

- [runner-compose.yml](/home/joe/repo/gpu-devops/runner-compose.yml): Runner deployment only. It defines the `gitlab-runner` service used for registration and steady-state operation.
- [docker-compose.yml](/home/joe/repo/gpu-devops/docker-compose.yml): local CUDA/C++ project build and dependency-cache preparation. It defines one build container and one dependency-preparation container per supported Linux builder platform.

Wrapper scripts:

- [runner-compose.sh](/home/joe/repo/gpu-devops/scripts/runner-compose.sh) targets `runner-compose.yml`
- [compose.sh](/home/joe/repo/gpu-devops/scripts/compose.sh) targets `docker-compose.yml`

Project build containers started through `scripts/compose.sh` now run as the current host caller UID/GID by default. On Linux, the project-side Docker entrypoints also require a rootless Docker daemon by default. This limits cross-user access to bind-mounted project files in shared Linux Docker environments, but it does not change the Docker daemon itself into rootless mode for you. Set `CUDA_CXX_ALLOW_ROOTFUL_DOCKER=1` only when you need to keep a legacy rootful host temporarily. `runner-compose.yml` keeps its existing service behavior.

Local project build examples:

- Single platform: `scripts/compose.sh run --rm cuda-cxx-centos7`
- Multiple platforms: `scripts/compose.sh up --abort-on-container-exit cuda-cxx-centos7 cuda-cxx-ubuntu2204`
- Profile-based selection: `docker compose --profile centos7 --profile rocky8 -f docker-compose.yml up`

The build Compose file mounts the current host working tree into `/workspace`. `CUDA_CXX_PROJECT_DIR` is then resolved inside that workspace, build output is written to `CUDA_CXX_BUILD_ROOT/<platform>`, install output is written to `CUDA_CXX_INSTALL_ROOT/<platform>`, and heavy dependency caches live under `CUDA_CXX_DEPS_ROOT/<platform>`.

Because these project containers now run with the caller's UID/GID, generated files on the host stay owned by that caller instead of container `root`. If the target build, install, or dependency directories are not writable by that user, the compose run fails explicitly instead of silently bypassing permissions as `root`.

For a ready-made `.env` example with custom `CUDA_CXX_CMAKE_ARGS` and `CUDA_CXX_BUILD_ARGS`, see [cuda-cxx.env.example](/home/joe/repo/gpu-devops/examples/env/cuda-cxx.env.example).

## Shared tag policy

- `gpu`: default shared GPU jobs
- `cuda`: jobs that require the standard CUDA toolchain
- `gpu-multi`: jobs that need the multi-GPU runner pool
- `cuda-11`: jobs pinned to the CUDA 11.7 platform baseline

The same tags can be used by the optional shell-runner path. In that mode, the job runs as the Linux user `gitlab-runner` and calls `.gpu-devops/scripts/compose.sh run --rm cuda-cxx-centos7` instead of using GitLab's Docker executor directly.

Internally, bundle-related implementations are now grouped under `scripts/export/`, `scripts/import/`, and `scripts/common/`, while the existing top-level commands remain the stable operator-facing entrypoints.

Single-GPU jobs should use `gpu`, `cuda`, `cuda-11`.

Multi-GPU jobs should use `gpu-multi`, `cuda`, `cuda-11`. The initial implementation treats the multi-GPU pool as a separate Runner registration with stricter concurrency.

`runner/config.template.toml` is included as the target runtime shape. In normal operation the authoritative `config.toml` is generated by GitLab Runner registration and stored under `runner/config/`.

## Publishing contract

The builder image family is:

`tf-particles/devops/cuda-builder:cuda11.7-cmake3.26`

The default supported tags are:

- `tf-particles/devops/cuda-builder:cuda11.7-cmake3.26-centos7`
- `tf-particles/devops/cuda-builder:cuda11.7-cmake3.26-rocky8`
- `tf-particles/devops/cuda-builder:cuda11.7-cmake3.26-ubuntu2204`

Projects should pin to a published immutable tag rather than `latest`.

All three builder Dockerfiles accept the same proxy build arguments from `scripts/build-builder-image.sh`. The `centos7` variant does not persist those proxy variables into the final image, but it does translate them into a temporary `yum.conf` proxy entry during package installation.

If you rebuild builder images or prepare offline dependency media frequently, pre-stage the third-party archives on the host:

```bash
scripts/prepare-third-party-cache.sh
```

This cache now covers `chrono`, `eigen3`, `openmpi`, and `muparserx`. `scripts/prepare-chrono-source-cache.sh` remains as a compatibility wrapper for the Chrono-only path.

Heavy project dependencies are no longer baked into the base builder image. The same dependency-cache workflow can also prepare project-local copies of `Eigen3` and `OpenMPI` when an offline or cross-host install needs them:

```bash
scripts/prepare-builder-deps.sh --platform centos7
scripts/install-third-party.sh --host linux --platform centos7
```

That cache is stored under `CUDA_CXX_DEPS_ROOT/<platform>` and is then reused by `scripts/compose.sh run --rm cuda-cxx-centos7`, shell-runner Linux jobs, and offline no-checkout deployments. For Windows/MSVC hosts, use:

```bash
scripts/install-third-party.sh --host windows --deps chrono,eigen3,openmpi,muparserx
```

On Windows, the MPI dependency is installed as `MS-MPI` instead of `OpenMPI`.

The third-party entrypoints now resolve dependencies from a shared registry. `--deps` selects the target packages, and the scripts automatically add required upstream packages and run them in dependency order. For example, `--deps h5engine` resolves to `hdf5,h5engine`.

## Offline image bundle

The Runner service image is now treated as a first-class platform asset. In an online environment, prepare it before exporting:

```bash
scripts/prepare-runner-service-image.sh
```

By default this script pulls `RUNNER_SERVICE_SOURCE_IMAGE` and retags it to `RUNNER_SERVICE_IMAGE`. If you want a controlled local build entry point instead, use:

```bash
scripts/prepare-runner-service-image.sh --mode build
```

The exported Runner service image tag is determined by `RUNNER_SERVICE_IMAGE` in your active `.env`. If your offline environment is expected to run `tf-particles/devops/gitlab-runner:alpine-v16.10.1`, do not leave `RUNNER_SERVICE_IMAGE` set to the upstream source tag.

For air-gapped deployment, `scripts/export-images.sh` writes a compressed archive containing every builder tag derived from `BUILDER_IMAGE_FAMILY` and `BUILDER_PLATFORMS`, plus `RUNNER_DOCKER_IMAGE` and `RUNNER_SERVICE_IMAGE`. It also writes a sibling SHA256 file at `<archive>.sha256`. Copy both files to the target host and load the archive with `scripts/import-images.sh`.

If you only need part of that image set, you can export a smaller archive:

```bash
scripts/export-images.sh --only-runner-service --output artifacts/offline-runner-service.tar.gz
scripts/export-images.sh --only-build-images --output artifacts/offline-build-images.tar.gz
scripts/export-images.sh --only-build-images --platform centos7 --output artifacts/offline-build-images-centos7.tar.gz
```

`--only-runner-service` exports only `RUNNER_SERVICE_IMAGE`. `--only-build-images` exports only the builder image matrix and skips both Runner images. Add `--platform <name>` together with `--only-build-images` when you want a single builder tag such as `centos7`.

By default, `scripts/import-images.sh` verifies the SHA256 sidecar before calling `docker load`. Use `--skip-hash-check` only if you intentionally want to bypass integrity checking.

The image-only scripts and the project bundle scripts now share the same underlying image export/import implementation, so the difference between them is output format and installed assets, not a separate Docker save/load path.

An offline host can only start `scripts/runner-compose.sh up -d` after `RUNNER_SERVICE_IMAGE` has already been imported into the local Docker daemon. `runner-compose.yml` does not build or pull that image by itself in an air-gapped environment.

### End-to-end online/offline workflow

Use this sequence when you need to prepare the full platform on a connected host and then deploy it on an air-gapped host:

1. Online host:
   - `cp .env.example .env`
   - fill `GITLAB_URL`, `RUNNER_REGISTRATION_TOKEN`, and image names
   - `scripts/verify-host.sh`
   - `scripts/build-builder-image.sh --all-platforms`
   - `scripts/prepare-runner-service-image.sh`
   - `scripts/export-images.sh`
2. Copy `artifacts/offline-images.tar.gz` and `artifacts/offline-images.tar.gz.sha256` to the offline host.
3. Offline host:
   - `scripts/import-images.sh --input artifacts/offline-images.tar.gz`
   - `scripts/prepare-builder-deps.sh --platform centos7`
   - `scripts/install-third-party.sh --host linux --platform centos7`
   - `scripts/runner-compose.sh up -d`
   - `runner/register-runner.sh gpu`
   - optional: `runner/register-runner.sh multi`
   - `scripts/compose.sh run --rm cuda-cxx-centos7`

If the offline host already has this repository checked out, you can import the toolkit with the repository script:

```bash
scripts/export-project-bundle.sh --mode assets --output artifacts/project-operator-toolkit.tar.gz
scripts/import-project-bundle.sh --mode assets --input artifacts/project-operator-toolkit.tar.gz --target-dir /path/to/project
```

If the offline host does not have this repository checked out, export the same toolkit on the online host and unpack it manually on the offline host:

```bash
mkdir -p /path/to/project/.gpu-devops
tmpdir="$(mktemp -d)"
tar -xzf artifacts/project-operator-toolkit.tar.gz -C "${tmpdir}"
cp -R "${tmpdir}/assets/." /path/to/project/.gpu-devops/
```

Then create `.gpu-devops/.env` by following [docs/offline-env-configuration.md](/home/joe/repo/gpu-devops/docs/offline-env-configuration.md), and continue from `/path/to/project/.gpu-devops/`:

Before using `.gpu-devops/scripts/compose.sh` or `.gpu-devops/scripts/prepare-builder-deps.sh` on the offline host, finish the rootless Docker setup described in [docs/offline-env-configuration.md](/home/joe/repo/gpu-devops/docs/offline-env-configuration.md). Linux project-side Docker entrypoints now require rootless Docker by default; `CUDA_CXX_ALLOW_ROOTFUL_DOCKER=1` is only a temporary compatibility bypass for legacy hosts.

```bash
.gpu-devops/scripts/import-images.sh --input /path/to/offline-images.tar.gz
.gpu-devops/scripts/prepare-builder-deps.sh --platform centos7
.gpu-devops/scripts/install-third-party.sh --host linux --platform centos7
.gpu-devops/scripts/runner-compose.sh up -d
.gpu-devops/runner/register-runner.sh gpu
.gpu-devops/runner/register-shell-runner.sh gpu
.gpu-devops/scripts/compose.sh run --rm cuda-cxx-centos7
```

## Project integration bundle

When another project lives outside this repository and still needs exported images, ready-to-use integration assets, or both, use:

- `scripts/export-project-bundle.sh`
- `scripts/import-project-bundle.sh --target-dir /path/to/other/project`

The project bundle scripts now support three modes:

- `--mode all`: export/import images and assets together
- `--mode images`: export/import images only
- `--mode assets`: export/import files only

Typical examples:

- `scripts/export-project-bundle.sh --mode images`
- `scripts/import-project-bundle.sh --mode images --input artifacts/project-integration-bundle.tar.gz`
- `scripts/export-project-bundle.sh --mode assets`
- `scripts/import-project-bundle.sh --mode assets --target-dir /path/to/other/project`

Every exported project bundle also produces `<bundle>.sha256`, and the import script verifies it by default before unpacking. In `all` and `images` mode, the nested `images/offline-images.tar.gz` is verified the same way. Use `--skip-hash-check` only when you explicitly need to bypass those checks.

In `all` mode, the exported bundle contains:

- the current offline image archive
- `.env.example`
- `docker-compose.yml`
- `runner-compose.yml`
- `examples/gitlab-ci/shared-gpu-runner.yml`
- the full operator script toolkit, including image import/export and Runner image preparation
- `runner/register-runner.sh` and `runner/config.template.toml`
- `docker/cuda-builder/` and `docker/gitlab-runner/` so imported build and prepare scripts keep working
- the operator/tutorial docs

Importing the bundle in `all` mode loads the images into Docker and installs those assets under `<target>/.gpu-devops/` by default, so the target project does not need to live under the current repository tree and does not risk overwriting its own root-level files.

That imported `.gpu-devops/` directory is now a functional operator toolkit. Beyond local project builds, it can also run:

- `.gpu-devops/scripts/verify-host.sh`
- `.gpu-devops/scripts/build-builder-image.sh --all-platforms`
- `.gpu-devops/scripts/prepare-runner-service-image.sh`
- `.gpu-devops/scripts/export-images.sh`
- `.gpu-devops/scripts/import-images.sh`
- `.gpu-devops/scripts/runner-compose.sh up -d`
- `.gpu-devops/runner/register-runner.sh gpu`
- `.gpu-devops/runner/register-shell-runner.sh gpu`

When assets are imported, the importer also writes `<target>/.gpu-devops/.env` with target-safe defaults:

- `HOST_PROJECT_DIR=<target project root>`
- `CUDA_CXX_PROJECT_DIR=.`
- `CUDA_CXX_BUILD_ROOT=.gpu-devops/artifacts/cuda-cxx-build`
- `CUDA_CXX_INSTALL_ROOT=.gpu-devops/artifacts/cuda-cxx-install`

## Project usage

See [examples/gitlab-ci/shared-gpu-runner.yml](/home/joe/repo/gpu-devops/examples/gitlab-ci/shared-gpu-runner.yml) for a complete example.

Additional reference docs:

- [docs/operations.md](/home/joe/repo/gpu-devops/docs/operations.md)
- [docs/self-check.md](/home/joe/repo/gpu-devops/docs/self-check.md)
- [docs/platform-contract.md](/home/joe/repo/gpu-devops/docs/platform-contract.md)
- [docs/project-devops-capability-assessment.md](/home/joe/repo/gpu-devops/docs/project-devops-capability-assessment.md)
- [docs/operations.md](/home/joe/repo/gpu-devops/docs/operations.md)
- [docs/offline-env-configuration.md](/home/joe/repo/gpu-devops/docs/offline-env-configuration.md)

## Limitations

- No Kubernetes deployment in v1
- No autoscaling in v1
- No support for multiple CUDA major versions in v1
- Multi-GPU scheduling is implemented as a dedicated Runner pool, not fine-grained per-job GPU reservation
