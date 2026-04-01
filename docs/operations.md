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
scripts/prepare-chrono-source-cache.sh
scripts/build-builder-image.sh
scripts/build-builder-image.sh --platform ubuntu2204
scripts/build-builder-image.sh --all-platforms
scripts/prepare-runner-service-image.sh
scripts/export-images.sh
scripts/runner-compose.sh up -d
```

`scripts/prepare-chrono-source-cache.sh` is optional. Use it when repeated builder-image rebuilds spend too much time downloading Chrono. It generates `docker/cuda-builder/deps/chrono-source.tar.gz`, which the Dockerfiles consume before falling back to the online git path.

The published builder images now keep only the common toolchain baseline. Heavy project dependencies such as Chrono, HDF5, h5engine, and muparserx are prepared later into `CUDA_CXX_DEPS_ROOT/<platform>` with:

```bash
scripts/prepare-builder-deps.sh --platform centos7
```

If the destination host is air-gapped, copy the archive referenced by `IMAGE_ARCHIVE_PATH` to that host and run:

```bash
scripts/import-images.sh
```

For a complete online-to-offline deployment workflow, use this order:

1. Online host:
   - `cp .env.example .env`
   - fill `GITLAB_URL`, `RUNNER_REGISTRATION_TOKEN`, and published image names
   - `scripts/verify-host.sh`
   - `scripts/build-builder-image.sh --all-platforms`
   - `scripts/prepare-runner-service-image.sh`
   - `scripts/export-images.sh`
2. Transfer `IMAGE_ARCHIVE_PATH` and `${IMAGE_ARCHIVE_PATH}.sha256` to the offline host.
3. Offline host:
   - `scripts/import-images.sh --input "${IMAGE_ARCHIVE_PATH}"`
   - `scripts/prepare-builder-deps.sh --platform centos7`
   - `scripts/runner-compose.sh up -d`
   - `runner/register-runner.sh gpu`
   - optional: `runner/register-runner.sh multi`
   - `scripts/compose.sh run --rm cuda-cxx-centos7`

If the offline host keeps a full checkout of this repository, export the operator toolkit on the online host:

```bash
scripts/export-project-bundle.sh --mode assets --output artifacts/project-operator-toolkit.tar.gz
```

Then import it on the offline host with the repository script:

```bash
scripts/import-project-bundle.sh --mode assets --input artifacts/project-operator-toolkit.tar.gz --target-dir /path/to/project
```

Continue all later commands from `/path/to/project/.gpu-devops/`.

If the offline host does not keep a full checkout, unpack the same toolkit archive manually:

```bash
mkdir -p /path/to/project/.gpu-devops
tmpdir="$(mktemp -d)"
tar -xzf artifacts/project-operator-toolkit.tar.gz -C "${tmpdir}"
cp -R "${tmpdir}/assets/." /path/to/project/.gpu-devops/
cat > /path/to/project/.gpu-devops/.env <<'EOF'
HOST_PROJECT_DIR=/path/to/project
CUDA_CXX_PROJECT_DIR=.
CUDA_CXX_BUILD_ROOT=.gpu-devops/artifacts/cuda-cxx-build
CUDA_CXX_INSTALL_ROOT=.gpu-devops/artifacts/cuda-cxx-install
CUDA_CXX_DEPS_ROOT=.gpu-devops/artifacts/deps
CUDA_CXX_CMAKE_GENERATOR=Ninja
CUDA_CXX_CMAKE_ARGS=
CUDA_CXX_BUILD_ARGS=
EOF
```

Then continue from `/path/to/project/.gpu-devops/`:

```bash
.gpu-devops/scripts/import-images.sh --input /path/to/offline-images.tar.gz
.gpu-devops/scripts/prepare-builder-deps.sh --platform centos7
.gpu-devops/scripts/runner-compose.sh up -d
.gpu-devops/runner/register-runner.sh gpu
.gpu-devops/runner/register-shell-runner.sh gpu
.gpu-devops/scripts/compose.sh run --rm cuda-cxx-centos7
```

`scripts/prepare-runner-service-image.sh` gives `RUNNER_SERVICE_IMAGE` a controlled online preparation step before export. Its default `retag` mode pulls `RUNNER_SERVICE_SOURCE_IMAGE` and retags it to `RUNNER_SERVICE_IMAGE`. If you want a repo-local build entry point for later customization, run:

```bash
scripts/prepare-runner-service-image.sh --mode build
```

If your GitLab HTTPS endpoint uses a self-signed certificate, set `RUNNER_TLS_CA_FILE` in `.env` before running `runner/register-runner.sh`. The registration script copies that PEM file into `runner/config/certs/<gitlab-host>.crt` and passes `--tls-ca-file` to the registration container automatically.

`scripts/export-images.sh` also writes `${IMAGE_ARCHIVE_PATH}.sha256`. `scripts/import-images.sh` verifies that hash by default before loading the archive. Add `--skip-hash-check` only when you intentionally want to bypass integrity checking.

When you do not need the full image set, `scripts/export-images.sh` also supports:

```bash
scripts/export-images.sh --only-runner-service --output artifacts/offline-runner-service.tar.gz
scripts/export-images.sh --only-build-images --output artifacts/offline-build-images.tar.gz
scripts/export-images.sh --only-build-images --platform centos7 --output artifacts/offline-build-images-centos7.tar.gz
```

Use `--only-runner-service` to refresh just `RUNNER_SERVICE_IMAGE` on an offline host that already has the builder images. Use `--only-build-images` when you want only the builder image matrix and do not need the Runner images in that archive. Add `--platform <name>` when you want a single builder tag such as `centos7`.

These image-only scripts share the same image export/import implementation as the project bundle scripts. The main difference is that they produce and consume the plain offline image archive directly.

On an offline host, `scripts/runner-compose.sh up -d` assumes `RUNNER_SERVICE_IMAGE` is already present locally because `runner-compose.yml` only runs the service image and does not build it.

To move the same images and integration assets into another project directory outside this repository, run:

```bash
scripts/export-project-bundle.sh
scripts/import-project-bundle.sh --target-dir /path/to/other/project
```

The imported files are installed under `/path/to/other/project/.gpu-devops/` by default.

The importer also generates `/path/to/other/project/.gpu-devops/.env` so the copied `compose.sh` mounts the target project root and treats that root as the default source tree. The generated file now includes `CUDA_CXX_BUILD_ROOT`, `CUDA_CXX_INSTALL_ROOT`, and `CUDA_CXX_DEPS_ROOT`.

The imported `.gpu-devops/` directory now behaves as a functional operator toolkit, not just a minimal project integration stub. It includes:

- image import/export scripts
- Runner service image preparation
- builder image build scripts plus `docker/cuda-builder/`
- Runner registration assets under `runner/`
- the existing Compose wrappers and docs

The project bundle scripts also support partial flows:

```bash
scripts/export-project-bundle.sh --mode images
scripts/import-project-bundle.sh --mode images --input artifacts/project-integration-bundle.tar.gz

scripts/export-project-bundle.sh --mode assets
scripts/import-project-bundle.sh --mode assets --target-dir /path/to/other/project
```

`--mode images` does not require `--target-dir`. `--mode assets` skips Docker image import and only installs the copied files.

Each exported project bundle also produces a sibling `.sha256` file, and the importer verifies it by default before unpacking. In `all` and `images` mode, the nested image archive is verified as well. Use `--skip-hash-check` only if you need to bypass those checks deliberately.

For a field-by-field explanation of offline `.env` values, including Docker executor, shell runner, and self-signed GitLab HTTPS setup, see [offline-env-configuration.md](/home/joe/repo/gpu-devops/docs/offline-env-configuration.md).

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
scripts/prepare-builder-deps.sh --platform centos7
scripts/compose.sh run --rm cuda-cxx-centos7
scripts/compose.sh up --abort-on-container-exit cuda-cxx-centos7 cuda-cxx-ubuntu2204
```

If you want a ready-made `.env` example that already customizes `CUDA_CXX_CMAKE_ARGS` and `CUDA_CXX_BUILD_ARGS`, start from [cuda-cxx.env.example](/home/joe/repo/gpu-devops/examples/env/cuda-cxx.env.example).

The current host directory is mounted to `/workspace`. `CUDA_CXX_PROJECT_DIR` selects the source subtree inside `/workspace`, build outputs are written to `CUDA_CXX_BUILD_ROOT/<platform>`, install outputs are written to `CUDA_CXX_INSTALL_ROOT/<platform>`, and the prepared dependency cache is reused from `CUDA_CXX_DEPS_ROOT/<platform>`.

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
