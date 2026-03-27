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
scripts/prepare-runner-service-image.sh
scripts/export-images.sh
scripts/runner-compose.sh up -d
```

If the destination host is air-gapped, copy the archive referenced by `IMAGE_ARCHIVE_PATH` to that host and run:

```bash
scripts/import-images.sh
```

`scripts/prepare-runner-service-image.sh` gives `RUNNER_SERVICE_IMAGE` a controlled online preparation step before export. Its default `retag` mode pulls `RUNNER_SERVICE_SOURCE_IMAGE` and retags it to `RUNNER_SERVICE_IMAGE`. If you want a repo-local build entry point for later customization, run:

```bash
scripts/prepare-runner-service-image.sh --mode build
```

`scripts/export-images.sh` also writes `${IMAGE_ARCHIVE_PATH}.sha256`. `scripts/import-images.sh` verifies that hash by default before loading the archive. Add `--skip-hash-check` only when you intentionally want to bypass integrity checking.

These image-only scripts share the same image export/import implementation as the project bundle scripts. The main difference is that they produce and consume the plain offline image archive directly.

On an offline host, `scripts/runner-compose.sh up -d` assumes `RUNNER_SERVICE_IMAGE` is already present locally because `runner-compose.yml` only runs the service image and does not build it.

To move the same images and integration assets into another project directory outside this repository, run:

```bash
scripts/export-project-bundle.sh
scripts/import-project-bundle.sh --target-dir /path/to/other/project
```

The imported files are installed under `/path/to/other/project/.gpu-devops/` by default.

The importer also generates `/path/to/other/project/.gpu-devops/.env` so the copied `compose.sh` mounts the target project root and treats that root as the default source tree.

The project bundle scripts also support partial flows:

```bash
scripts/export-project-bundle.sh --mode images
scripts/import-project-bundle.sh --mode images --input artifacts/project-integration-bundle.tar.gz

scripts/export-project-bundle.sh --mode assets
scripts/import-project-bundle.sh --mode assets --target-dir /path/to/other/project
```

`--mode images` does not require `--target-dir`. `--mode assets` skips Docker image import and only installs the copied files.

Each exported project bundle also produces a sibling `.sha256` file, and the importer verifies it by default before unpacking. In `all` and `images` mode, the nested image archive is verified as well. Use `--skip-hash-check` only if you need to bypass those checks deliberately.

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

Proxy handling is aligned across `centos7`, `rocky8`, and `ubuntu2204`: the build wrapper passes the same proxy inputs to every platform. `centos7` additionally maps that input into a temporary `yum.conf` proxy entry so legacy package installation still works without baking proxy environment variables into the final image.

## Upgrade path

1. Build and publish a new builder image tag.
2. Prepare and publish the updated `RUNNER_SERVICE_IMAGE` with `scripts/prepare-runner-service-image.sh` if the Runner service image source or target changes.
3. Update `BUILDER_IMAGE_FAMILY`, `BUILDER_DEFAULT_PLATFORM`, `BUILDER_PLATFORMS`, `RUNNER_DOCKER_IMAGE`, `RUNNER_SERVICE_IMAGE`, and `BUILDER_IMAGE` in `.env` if the platform matrix or published image names change.
4. Re-export the offline image bundle if air-gapped hosts depend on it.
5. Restart the Runner service.
6. Validate the smoke pipeline in a test project.

## Rollback

1. Restore the previous image tag in `.env`.
2. Restart the Runner service.
3. Re-run the smoke pipeline.

## Cache management

Runner cache is stored under `runner/cache/`. Remove stale cache content during maintenance windows if jobs accumulate too much local state.
