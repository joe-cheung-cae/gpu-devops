# Shared GitLab GPU Runner Platform

This repository provides a shared GitLab CI/CD platform for CUDA and CMake based projects. It ships:

- A standard CUDA builder image for project jobs
- Multiple builder platform variants: `centos7`, `rocky8`, `ubuntu2204`
- A Docker Compose based GitLab Runner deployment for GPU workloads
- A Docker Compose based local CUDA/C++ build workflow for one or more builder platforms
- Registration and verification scripts
- Example GitLab CI and a minimal CUDA/CMake smoke project

The first release targets a single host with NVIDIA GPUs and shared Runner usage across multiple projects.

The shared builder images include a pinned math and simulation baseline:

- Eigen3 `3.4.0`, installed from source to `/usr/local`
- Project Chrono at commit `3eb56218b`, cloned into `${HOME}/deps/chrono` and installed to `${HOME}/deps/chrono-install`
- HDF5 `1.14.1-2`, built from the bundled `docker/cuda-builder/deps/CMake-hdf5-1.14.1-2.tar.gz` archive and installed to `${HOME}/deps/hdf5-install`
- `h5engine-sph`, unpacked to `${HOME}/deps/h5engine-sph` and rebuilt against the installed HDF5 runtime
- `h5engine-dem`, unpacked to `${HOME}/deps/h5engine-dem` and rebuilt against the installed HDF5 runtime
- `muparserx`, cloned from `master` into `${HOME}/deps/muparserx` and installed to `${HOME}/deps/muparserx-install`

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
   Single platform: `scripts/build-builder-image.sh --platform ubuntu2204`
   All supported platforms: `scripts/build-builder-image.sh --all-platforms`
4. Prepare the Runner service image with `scripts/prepare-runner-service-image.sh`.
5. If the target host is air-gapped, export the deployment images with `scripts/export-images.sh`.
6. Start the Runner service with `scripts/runner-compose.sh up -d`.
7. Register Runner entries with `runner/register-runner.sh`.
8. Validate the deployment with `docs/self-check.md`.

## Compose files

- [runner-compose.yml](/home/joe/repo/gpu-devops/runner-compose.yml): Runner deployment only. It defines the `gitlab-runner` service used for registration and steady-state operation.
- [docker-compose.yml](/home/joe/repo/gpu-devops/docker-compose.yml): local CUDA/C++ project build only. It runs one build container per supported builder platform.

Wrapper scripts:

- [runner-compose.sh](/home/joe/repo/gpu-devops/scripts/runner-compose.sh) targets `runner-compose.yml`
- [compose.sh](/home/joe/repo/gpu-devops/scripts/compose.sh) targets `docker-compose.yml`

Local project build examples:

- Single platform: `scripts/compose.sh run --rm cuda-cxx-centos7`
- Multiple platforms: `scripts/compose.sh up --abort-on-container-exit cuda-cxx-centos7 cuda-cxx-ubuntu2204`
- Profile-based selection: `docker compose --profile centos7 --profile rocky8 -f docker-compose.yml up`

The build Compose file mounts the current host working tree into `/workspace`. `CUDA_CXX_PROJECT_DIR` is then resolved inside that workspace, and build output is written to `CUDA_CXX_BUILD_ROOT/<platform>`.

For a ready-made `.env` example with custom `CUDA_CXX_CMAKE_ARGS` and `CUDA_CXX_BUILD_ARGS`, see [cuda-cxx.env.example](/home/joe/repo/gpu-devops/examples/env/cuda-cxx.env.example).

## Shared tag policy

- `gpu`: default shared GPU jobs
- `cuda`: jobs that require the standard CUDA toolchain
- `gpu-multi`: jobs that need the multi-GPU runner pool
- `cuda-11`: jobs pinned to the CUDA 11.7 platform baseline

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

Chrono is configured with `-DUSE_BULLET_DOUBLE=ON -DUSE_SIMD=OFF`. `ChronoEngine` is explicitly linked with `-static-libgcc -static-libstdc++`, so `libChronoEngine.so` does not retain dynamic `libstdc++.so` or `libgcc_s.so` dependencies.

HDF5 is built from the repo-local `CMake-hdf5-1.14.1-2.tar.gz` archive with zlib enabled and installed to `${HOME}/deps/hdf5-install`. The runtime validation command is `ldd ${HOME}/deps/hdf5-install/lib/libhdf5.so`.

Both `h5engine-sph` and `h5engine-dem` are rebuilt from the bundled tarballs after HDF5 installation. During image build, each package refreshes `third/hdf5/include/linux` and `third/hdf5/lib/linux` from `${HOME}/deps/hdf5-install`, then runs `cmake .. -DCMAKE_BUILD_TYPE=Release`, `make -j6`, `ldd ./build/h5Engine/libh5Engine.so`, and `./build/testHdf5`.

`muparserx` is cloned directly from `https://github.com/joe-cheung-cae/muparserx.git`, reset to `master`, configured in `${HOME}/deps/muparserx/build`, and installed to `${HOME}/deps/muparserx-install`. The runtime validation command is `ldd ${HOME}/deps/muparserx/build/libmuparserx.so`.

## Offline image bundle

The Runner service image is now treated as a first-class platform asset. In an online environment, prepare it before exporting:

```bash
scripts/prepare-runner-service-image.sh
```

By default this script pulls `RUNNER_SERVICE_SOURCE_IMAGE` and retags it to `RUNNER_SERVICE_IMAGE`. If you want a controlled local build entry point instead, use:

```bash
scripts/prepare-runner-service-image.sh --mode build
```

For air-gapped deployment, `scripts/export-images.sh` writes a compressed archive containing every builder tag derived from `BUILDER_IMAGE_FAMILY` and `BUILDER_PLATFORMS`, plus `RUNNER_DOCKER_IMAGE` and `RUNNER_SERVICE_IMAGE`. It also writes a sibling SHA256 file at `<archive>.sha256`. Copy both files to the target host and load the archive with `scripts/import-images.sh`.

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
cat > /path/to/project/.gpu-devops/.env <<'EOF'
HOST_PROJECT_DIR=/path/to/project
CUDA_CXX_PROJECT_DIR=.
CUDA_CXX_BUILD_ROOT=.gpu-devops/artifacts/cuda-cxx-build
CUDA_CXX_CMAKE_GENERATOR=Ninja
CUDA_CXX_CMAKE_ARGS=
CUDA_CXX_BUILD_ARGS=
EOF
```

Then continue from `/path/to/project/.gpu-devops/`:

```bash
.gpu-devops/scripts/import-images.sh --input /path/to/offline-images.tar.gz
.gpu-devops/scripts/runner-compose.sh up -d
.gpu-devops/runner/register-runner.sh gpu
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

When assets are imported, the importer also writes `<target>/.gpu-devops/.env` with target-safe defaults:

- `HOST_PROJECT_DIR=<target project root>`
- `CUDA_CXX_PROJECT_DIR=.`
- `CUDA_CXX_BUILD_ROOT=.gpu-devops/artifacts/cuda-cxx-build`

## Project usage

See [examples/gitlab-ci/shared-gpu-runner.yml](/home/joe/repo/gpu-devops/examples/gitlab-ci/shared-gpu-runner.yml) for a complete example.

Additional reference docs:

- [docs/operations.md](/home/joe/repo/gpu-devops/docs/operations.md)
- [docs/self-check.md](/home/joe/repo/gpu-devops/docs/self-check.md)
- [docs/platform-contract.md](/home/joe/repo/gpu-devops/docs/platform-contract.md)
- [docs/project-devops-capability-assessment.md](/home/joe/repo/gpu-devops/docs/project-devops-capability-assessment.md)

## Limitations

- No Kubernetes deployment in v1
- No autoscaling in v1
- No support for multiple CUDA major versions in v1
- Multi-GPU scheduling is implemented as a dedicated Runner pool, not fine-grained per-job GPU reservation
