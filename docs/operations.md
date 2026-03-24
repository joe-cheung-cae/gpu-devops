# Operations Guide

## Host preparation

1. Install Docker Engine.
2. Install Docker Compose plugin or standalone `docker-compose`.
3. Install the NVIDIA driver.
4. Install NVIDIA Container Toolkit and configure Docker to expose the `nvidia` runtime.
5. Reboot or restart Docker if runtime changes are not visible.

## Bootstrap

```bash
cp .env.example .env
scripts/verify-host.sh
scripts/build-builder-image.sh
scripts/build-builder-image.sh --platform ubuntu2204
scripts/build-builder-image.sh --all-platforms
scripts/export-images.sh
scripts/runner-compose.sh up -d
```

If the destination host is air-gapped, copy the archive referenced by `IMAGE_ARCHIVE_PATH` to that host and run:

```bash
scripts/import-images.sh
```

To move the same images and integration assets into another project directory outside this repository, run:

```bash
scripts/export-project-bundle.sh
scripts/import-project-bundle.sh --target-dir /path/to/other/project
```

The imported files are installed under `/path/to/other/project/.gpu-devops/` by default.

The importer also generates `/path/to/other/project/.gpu-devops/.env` so the copied `compose.sh` mounts the target project root and treats that root as the default source tree.

## Runner registration

Register the standard GPU pool:

```bash
runner/register-runner.sh gpu
```

Register the multi-GPU pool:

```bash
runner/register-runner.sh multi
```

Both registrations append to `runner/config/config.toml`.

## Local project build

Use `docker-compose.yml` when you want to compile a CUDA/C++ project locally with one or more builder platforms instead of deploying GitLab Runner:

```bash
scripts/compose.sh run --rm cuda-cxx-centos7
scripts/compose.sh up --abort-on-container-exit cuda-cxx-centos7 cuda-cxx-ubuntu2204
```

If you want a ready-made `.env` example that already customizes `CUDA_CXX_CMAKE_ARGS` and `CUDA_CXX_BUILD_ARGS`, start from [cuda-cxx.env.example](/home/joe/repo/gpu-devops/examples/env/cuda-cxx.env.example).

The current host directory is mounted to `/workspace`. `CUDA_CXX_PROJECT_DIR` selects the source subtree inside `/workspace`, and build outputs are written to `CUDA_CXX_BUILD_ROOT/<platform>`.

## Upgrade path

1. Build and publish a new builder image tag.
2. Update `BUILDER_IMAGE_FAMILY`, `BUILDER_DEFAULT_PLATFORM`, `BUILDER_PLATFORMS`, `RUNNER_DOCKER_IMAGE`, and `BUILDER_IMAGE` in `.env` if the platform matrix changes.
3. Re-export the offline image bundle if air-gapped hosts depend on it.
4. Restart the Runner service.
5. Validate the smoke pipeline in a test project.

## Rollback

1. Restore the previous image tag in `.env`.
2. Restart the Runner service.
3. Re-run the smoke pipeline.

## Cache management

Runner cache is stored under `runner/cache/`. Remove stale cache content during maintenance windows if jobs accumulate too much local state.
