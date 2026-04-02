# GitLab GPU Shell Runner Tutorial

This tutorial is for:

- Platform operators who build the CUDA images and register the shell runners
- Project developers who consume the shared platform from `.gitlab-ci.yml`

The repository targets a single Docker host with NVIDIA GPUs. Jobs run through
the GitLab shell executor and call `compose.sh` to build inside the builder
images.

## 1. What the platform provides

- CUDA builder image family: `cuda11.7-cmake3.26-{centos7|rocky8|ubuntu2204}`
- Shell runner registration workflow
- Offline image export/import and portable operator toolkit
- Example CI pipeline and CUDA/CMake smoke project

Default tag policy:

- `gpu`: single-GPU jobs
- `gpu-multi`: multi-GPU jobs
- `cuda`: jobs that require CUDA toolchain support
- `cuda-11`: jobs pinned to the CUDA 11.7 platform baseline

## 2. Repository layout

- `docker/cuda-builder/`: standard CUDA builder image definition
- `runner/`: shell runner registration script
- `scripts/`: image build, compose wrapper, and host verification scripts
- `scripts/export/`, `scripts/import/`, `scripts/common/`: bundle internals
- `examples/`: minimal CUDA/CMake example and GitLab CI example
- `docs/`: operations, contract, and validation documents

## 3. Host prerequisites

Before deployment, the host should provide:

1. Docker Engine
2. Docker Compose plugin, or standalone `docker-compose`
3. NVIDIA driver
4. NVIDIA Container Toolkit with `nvidia` runtime available to Docker
5. Network access to container registries and base image mirrors

Verify the host:

```bash
scripts/verify-host.sh
```

Expected results:

- `docker --version` works
- `docker compose version` or `docker-compose --version` works
- `nvidia-smi` prints GPU information
- `docker info` exposes the `nvidia` runtime

## 4. Supported builder platforms

The builder family currently supports:

- `centos7` -> `nvidia/cuda:11.7.1-devel-centos7`
- `rocky8` -> `nvidia/cuda:11.7.1-devel-rockylinux8`
- `ubuntu2204` -> `nvidia/cuda:11.7.1-devel-ubuntu22.04`

Platform notes:

- `centos7` remains available for compatibility and uses `vault.centos.org`
- `centos7` keeps `urllib3<2` for OpenSSL compatibility
- all platforms keep the base image limited to the common CUDA/C++ toolchain
- project dependencies are prepared later into `${CUDA_CXX_DEPS_ROOT}/<platform>`

## 5. Configure environment variables

Create `.env`:

```bash
cp .env.example .env
```

Update the main fields:

- `GITLAB_URL`: GitLab base URL
- `RUNNER_REGISTRATION_TOKEN`: runner registration token
- `RUNNER_SHELL_USER`: Linux user that executes shell runner jobs
- `RUNNER_TLS_CA_FILE`: optional PEM-encoded CA certificate path
- `BUILDER_IMAGE_FAMILY`: image family prefix used for platform variants
- `BUILDER_DEFAULT_PLATFORM`: default Linux platform
- `BUILDER_PLATFORMS`: comma-separated list of build variants
- `BUILDER_IMAGE`: default builder tag
- `IMAGE_ARCHIVE_PATH`: offline image archive path
- `RUNNER_GPU_CONCURRENCY` and `RUNNER_MULTI_GPU_CONCURRENCY`

Recommended practice:

- Replace example registries with your internal registry
- Use explicit immutable tags instead of `latest`
- Set `RUNNER_TLS_CA_FILE` before runner registration if GitLab uses a
  self-signed certificate

## 6. Build the standard CUDA builder image

Run:

```bash
scripts/prepare-third-party-cache.sh
scripts/build-builder-image.sh
scripts/build-builder-image.sh --platform ubuntu2204
scripts/build-builder-image.sh --all-platforms
```

`scripts/prepare-third-party-cache.sh` is optional. It stages local archives
for `chrono`, `eigen3`, `openmpi`, and `muparserx`. `scripts/prepare-chrono-source-cache.sh`
remains as a Chrono-only compatibility wrapper.

Project dependencies such as Chrono, Eigen3, OpenMPI, HDF5, h5engine, and
muparserx are prepared later into `CUDA_CXX_DEPS_ROOT/<platform>` with:

```bash
scripts/prepare-builder-deps.sh --platform centos7
scripts/install-third-party.sh --host linux --platform centos7
```

## 7. Offline image export and import

On a connected host:

```bash
scripts/export-images.sh
```

The export writes `${IMAGE_ARCHIVE_PATH}` plus a sibling `.sha256`. Import on
the offline host with:

```bash
scripts/import-images.sh --input "${IMAGE_ARCHIVE_PATH}"
```

If the offline host does not keep a repository checkout, export the operator
toolkit and unpack it on the target host:

```bash
scripts/export-project-bundle.sh --mode assets --output artifacts/project-operator-toolkit.tar.gz
```

Then:

```bash
mkdir -p /path/to/project/.gpu-devops
tmpdir="$(mktemp -d)"
tar -xzf artifacts/project-operator-toolkit.tar.gz -C "${tmpdir}"
cp -R "${tmpdir}/assets/." /path/to/project/.gpu-devops/
```

Fill `.gpu-devops/.env` according to [offline-env-configuration.md](offline-env-configuration.md),
then continue from `/path/to/project/.gpu-devops/`:

```bash
.gpu-devops/scripts/import-images.sh --input /path/to/offline-images.tar.gz
.gpu-devops/scripts/prepare-builder-deps.sh --platform centos7
.gpu-devops/scripts/install-third-party.sh --host linux --platform centos7
.gpu-devops/runner/register-shell-runner.sh gpu
.gpu-devops/scripts/compose.sh run --rm cuda-cxx-centos7
```

If another project needs the same images and integration assets, use:

```bash
scripts/export-project-bundle.sh
scripts/import-project-bundle.sh --target-dir /path/to/other/project
```

## 8. Register shell runners

Register the standard GPU pool:

```bash
runner/register-shell-runner.sh gpu
```

Register the multi-GPU pool:

```bash
runner/register-shell-runner.sh multi
```

The shell-runner path runs jobs as `gitlab-runner` (or `RUNNER_SHELL_USER`) and
expects that user to access Docker and `docker compose`.

## 9. Local project build with Compose

Example local builds:

```bash
scripts/prepare-builder-deps.sh --platform centos7
scripts/install-third-party.sh --host linux --platform centos7
scripts/compose.sh run --rm cuda-cxx-centos7
scripts/compose.sh up --abort-on-container-exit cuda-cxx-centos7 cuda-cxx-ubuntu2204
```

`CUDA_CXX_PROJECT_DIR` selects the source subtree inside `/workspace`.
`CUDA_CXX_BUILD_ROOT` and `CUDA_CXX_INSTALL_ROOT` store outputs per platform.

For a ready-made `.env` example with custom `CUDA_CXX_CMAKE_ARGS` and
`CUDA_CXX_BUILD_ARGS`, see [cuda-cxx.env.example](../examples/env/cuda-cxx.env.example).

## 10. CI usage

See the shell-runner example:

- [examples/gitlab-ci/shared-gpu-shell-runner.yml](../examples/gitlab-ci/shared-gpu-shell-runner.yml)

The example uses `BUILD_PLATFORM=centos7` as the default Linux platform and
invokes `.gpu-devops/scripts/compose.sh` inside each job.

## 11. Troubleshooting

### 11.1 CUDA base image cannot be pulled

Check:

- Docker daemon registry configuration
- proxy configuration
- whether Docker daemon needs a restart

Try pulling the base images directly:

```bash
docker pull nvidia/cuda:11.7.1-devel-centos7
docker pull nvidia/cuda:11.7.1-devel-rockylinux8
docker pull nvidia/cuda:11.7.1-devel-ubuntu22.04
```
