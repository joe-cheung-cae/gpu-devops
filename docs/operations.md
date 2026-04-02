# Operations Guide

## Host preparation

1. Install Docker Engine.
2. Install Docker Compose plugin or standalone `docker-compose`.
3. Install the NVIDIA driver.
4. Install NVIDIA Container Toolkit and configure Docker to expose the `nvidia` runtime.
5. Reboot or restart Docker if runtime changes are not visible.

Bundle-related implementation is now grouped under `scripts/export/`, `scripts/import/`, and `scripts/common/`. Operators should keep using the existing top-level wrapper commands for compatibility.

## Bootstrap

```bash
cp .env.example .env
scripts/verify-host.sh
scripts/prepare-third-party-cache.sh
scripts/build-builder-image.sh
scripts/build-builder-image.sh --platform ubuntu2204
scripts/build-builder-image.sh --all-platforms
scripts/export/images.sh
```

`scripts/prepare-third-party-cache.sh` is optional but recommended for offline preparation. It stages local archives for `chrono`, `eigen3`, `openmpi`, and `muparserx` under `docker/cuda-builder/deps/`. `Eigen3` and `OpenMPI` now use the same project-local dependency path as the other third-party packages, and `scripts/prepare-third-party-cache.sh --deps chrono` remains as a Chrono-only compatibility wrapper.

The published builder images now keep only the common toolchain baseline. Project dependencies such as Chrono, Eigen3, OpenMPI, HDF5, h5engine, and muparserx are prepared later into `CUDA_CXX_DEPS_ROOT/<platform>` with:

```bash
scripts/prepare-builder-deps.sh --platform centos7
scripts/install-third-party.sh --host linux --platform centos7
```

If the destination host is air-gapped, copy the archive referenced by `IMAGE_ARCHIVE_PATH` to that host and run:

```bash
scripts/import/images.sh
```

For a complete online-to-offline deployment workflow, use this order:

1. Online host:
   - `cp .env.example .env`
   - fill `GITLAB_URL`, `RUNNER_REGISTRATION_TOKEN`, and published image names
   - `scripts/verify-host.sh`
   - `scripts/build-builder-image.sh --all-platforms`
   - `scripts/export/images.sh`
2. Transfer `IMAGE_ARCHIVE_PATH` and `${IMAGE_ARCHIVE_PATH}.sha256` to the offline host.
3. Offline host:
   - `scripts/import/images.sh --input "${IMAGE_ARCHIVE_PATH}"`
   - `scripts/prepare-builder-deps.sh --platform centos7`
   - `scripts/install-third-party.sh --host linux --platform centos7`
   - `runner/register-shell-runner.sh gpu`
   - optional: `runner/register-shell-runner.sh multi`
   - `scripts/compose.sh run --rm cuda-cxx-centos7`

If the offline host keeps a full checkout of this repository, export the operator toolkit on the online host:

```bash
scripts/export/project-bundle.sh --mode assets --output artifacts/project-operator-toolkit.tar.gz
```

Then import it on the offline host with the repository script:

```bash
scripts/import/project-bundle.sh --mode assets --input artifacts/project-operator-toolkit.tar.gz --target-dir /path/to/project
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
.gpu-devops/scripts/import/images.sh --input /path/to/offline-images.tar.gz
.gpu-devops/scripts/prepare-builder-deps.sh --platform centos7
.gpu-devops/scripts/install-third-party.sh --host linux --platform centos7
.gpu-devops/runner/register-shell-runner.sh gpu
.gpu-devops/scripts/compose.sh run --rm cuda-cxx-centos7
```

If your GitLab HTTPS endpoint uses a self-signed certificate, set `RUNNER_TLS_CA_FILE` in `.env` before running `runner/register-shell-runner.sh`. The registration script copies that PEM file into `~/.gitlab-runner/certs/<gitlab-host>.crt` and passes `--tls-ca-file` to the registration command automatically.

`scripts/export/images.sh` also writes `${IMAGE_ARCHIVE_PATH}.sha256`. `scripts/import/images.sh` verifies that hash by default before loading the archive. Add `--skip-hash-check` only when you intentionally want to bypass integrity checking.

When you do not need the full image set, `scripts/export/images.sh` also supports:

```bash
scripts/export/images.sh --only-build-images --output artifacts/offline-build-images.tar.gz
scripts/export/images.sh --only-build-images --platform centos7 --output artifacts/offline-build-images-centos7.tar.gz
```

Use `--only-build-images` when you want only the builder image matrix. Add `--platform <name>` when you want a single builder tag such as `centos7`.

These image-only scripts share the same image export/import implementation as the project bundle scripts. The main difference is that they produce and consume the plain offline image archive directly.

To move the same images and integration assets into another project directory outside this repository, run:

```bash
scripts/export/project-bundle.sh
scripts/import/project-bundle.sh --target-dir /path/to/other/project
```

The imported files are installed under `/path/to/other/project/.gpu-devops/` by default.

The importer also generates `/path/to/other/project/.gpu-devops/.env` so the copied `compose.sh` mounts the target project root and treats that root as the default source tree. The generated file now includes `CUDA_CXX_BUILD_ROOT`, `CUDA_CXX_INSTALL_ROOT`, and `CUDA_CXX_DEPS_ROOT`.

The imported `.gpu-devops/` directory now behaves as a functional operator toolkit, not just a minimal project integration stub. It includes:

- image import/export scripts
- builder image build scripts plus `docker/cuda-builder/`
- shell-runner registration assets under `runner/`
- the existing Compose wrappers and docs

The project bundle scripts also support partial flows:

```bash
scripts/export/project-bundle.sh --mode images
scripts/import/project-bundle.sh --mode images --input artifacts/project-integration-bundle.tar.gz

scripts/export/project-bundle.sh --mode assets
scripts/import/project-bundle.sh --mode assets --target-dir /path/to/other/project
```

`--mode images` does not require `--target-dir`. `--mode assets` skips Docker image import and only installs the copied files.

Each exported project bundle also produces a sibling `.sha256` file, and the importer verifies it by default before unpacking. In `all` and `images` mode, the nested image archive is verified as well. Use `--skip-hash-check` only if you need to bypass those checks deliberately.

For a field-by-field explanation of offline `.env` values, including shell runner and self-signed GitLab HTTPS setup, see [offline-env-configuration.md](offline-env-configuration.md).

## Shell runner registration

Register the standard GPU pool:

```bash
runner/register-shell-runner.sh gpu
```

Register the multi-GPU pool:

```bash
runner/register-shell-runner.sh multi
```

Both registrations append to `~/.gitlab-runner/config.toml`.

## Local project build

Use `docker-compose.yml` when you want to compile a CUDA/C++ project locally with one or more builder platforms instead of deploying GitLab Runner:

```bash
scripts/prepare-builder-deps.sh --platform centos7
scripts/install-third-party.sh --host linux --platform centos7
scripts/compose.sh run --rm cuda-cxx-centos7
scripts/compose.sh up --abort-on-container-exit cuda-cxx-centos7 cuda-cxx-ubuntu2204
```

These project-side compose containers now run as the current Linux caller UID/GID by default, and `scripts/prepare-builder-deps.sh` uses the same identity for its direct `docker run` path. On Linux, both entrypoints now require a rootless Docker daemon by default; set `CUDA_CXX_ALLOW_ROOTFUL_DOCKER=1` only when you need a temporary compatibility bypass for a legacy host. This reduces cross-user access to bind-mounted files on shared Docker hosts. It is a project workflow hardening step, not a rootless Docker daemon deployment.

For Windows/MSVC hosts, use `scripts/install-third-party.sh --host windows`. That path prepares the same archive cache but installs `MS-MPI` instead of `OpenMPI`.

All third-party entrypoints now use the shared registry under `scripts/common/third-party-registry.sh`. When you pass `--deps`, the scripts automatically expand required upstream dependencies and execute them in dependency order.

If you want a ready-made `.env` example that already customizes `CUDA_CXX_CMAKE_ARGS` and `CUDA_CXX_BUILD_ARGS`, start from [cuda-cxx.env.example](../examples/env/cuda-cxx.env.example).

The current host directory is mounted to `/workspace`. `CUDA_CXX_PROJECT_DIR` selects the source subtree inside `/workspace`, build outputs are written to `CUDA_CXX_BUILD_ROOT/<platform>`, install outputs are written to `CUDA_CXX_INSTALL_ROOT/<platform>`, and the prepared dependency cache is reused from `CUDA_CXX_DEPS_ROOT/<platform>`.

If those target directories are not writable by the calling user, the compose workflow now fails with a normal permission error instead of falling back to container `root`.

Proxy handling is aligned across `centos7`, `rocky8`, and `ubuntu2204`: the build wrapper passes the same proxy inputs to every platform. `centos7` additionally maps that input into a temporary `yum.conf` proxy entry so legacy package installation still works without baking proxy environment variables into the final image.

## Upgrade path

1. Build and publish a new builder image tag.
2. Update `BUILDER_IMAGE_FAMILY`, `BUILDER_DEFAULT_PLATFORM`, `BUILDER_PLATFORMS`, and `BUILDER_IMAGE` in `.env` if the platform matrix or published image names change.
3. Re-export the offline image bundle if air-gapped hosts depend on it.
4. Re-run the shell runner registration if tags or host policy changed.
5. Validate the smoke pipeline in a test project using the shell-runner CI example.

## Rollback

1. Restore the previous image tag in `.env`.
2. Restart the Runner service.
3. Re-run the smoke pipeline.

## Cache management

Runner cache is stored under `runner/cache/`. Remove stale cache content during maintenance windows if jobs accumulate too much local state.
