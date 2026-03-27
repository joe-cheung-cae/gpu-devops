# GitLab GPU Runner Tutorial

This document is written for two audiences:

- Platform operators who build the CUDA image, deploy GitLab Runner, and register shared runners
- Project developers who consume the shared runner platform from their own `.gitlab-ci.yml`

The current repository targets a single Docker host with NVIDIA GPUs and shared usage across multiple CUDA/CMake projects.

## 1. What the platform provides

The platform includes:

- A CUDA builder image family: `cuda11.7-cmake3.26-{centos7|rocky8|ubuntu2204}`
- Docker-based GitLab Runner deployment assets
- A default GPU runner pool and a multi-GPU runner pool
- Host verification, self-check documentation, and example pipelines

Default tag policy:

- `gpu`: single-GPU jobs
- `gpu-multi`: multi-GPU jobs
- `cuda`: jobs that require CUDA toolchain support
- `cuda-11`: jobs pinned to the CUDA 11.7 platform baseline

## 2. Repository layout

- `docker/cuda-builder/`: standard CUDA builder image definition
- `runner/`: runner config template and registration script
- `scripts/`: image build, compose wrapper, and host verification scripts
- `examples/`: minimal CUDA/CMake example and GitLab CI example
- `docs/`: operations, contract, and validation documents

## 3. Host prerequisites

Before deployment, the host should provide:

1. Docker Engine
2. Docker Compose plugin, or standalone `docker-compose`
3. NVIDIA driver
4. NVIDIA Container Toolkit with `nvidia` runtime available to Docker
5. Network access to:
   - container registries
   - CentOS Vault, Rocky Linux mirrors, Ubuntu mirrors, or internal mirrors
   - GitHub Releases

Run the host verification script first:

```bash
scripts/verify-host.sh
```

Expected results:

- `docker --version` works
- `docker compose version` or `docker-compose --version` works
- `nvidia-smi` prints GPU information
- `docker info` exposes the `nvidia` runtime

## 3.1 Supported builder platforms

The builder family currently supports:

- `centos7` -> `nvidia/cuda:11.7.1-devel-centos7`
- `rocky8` -> `nvidia/cuda:11.7.1-devel-rockylinux8`
- `ubuntu2204` -> `nvidia/cuda:11.7.1-devel-ubuntu22.04`

Platform-specific notes:

- `centos7` remains available for compatibility, but it is end-of-life and rewrites YUM repositories to `vault.centos.org`
- `centos7` uses `rh-python38` and keeps `urllib3<2` for OpenSSL compatibility
- `centos7` accepts the same proxy build arguments as the other platforms, but only uses them to generate a temporary `yum.conf` proxy during package install
- all three platforms install Eigen3 `3.4.0` from source to `/usr/local`
- all three platforms clone Project Chrono to `${HOME}/deps/chrono`, pin it to commit `3eb56218b`, and install it to `${HOME}/deps/chrono-install`
- all three platforms build HDF5 `1.14.1-2` from `docker/cuda-builder/deps/CMake-hdf5-1.14.1-2.tar.gz` and install it to `${HOME}/deps/hdf5-install`
- all three platforms unpack `h5engine-sph` and `h5engine-dem` into `${HOME}/deps`, refresh `third/hdf5/include/linux` and `third/hdf5/lib/linux` from the installed HDF5 tree, and rebuild them in `Release`
- all three platforms clone `muparserx` into `${HOME}/deps/muparserx`, force checkout `master`, build it in `${HOME}/deps/muparserx/build`, and install it to `${HOME}/deps/muparserx-install`
- `rocky8` and `ubuntu2204` use newer system Python packages and avoid the CentOS 7 compatibility pin

## 4. Configure environment variables

Create a local `.env` file:

```bash
cp .env.example .env
```

Then update the main fields:

- `GITLAB_URL`: GitLab base URL
- `BUILDER_IMAGE_FAMILY`: image family prefix used for all platform variants
- `BUILDER_DEFAULT_PLATFORM`: platform tag used by `BUILDER_IMAGE` and the runner default image
- `BUILDER_PLATFORMS`: comma-separated list of supported build variants
- `RUNNER_REGISTRATION_TOKEN`: runner registration token
- `RUNNER_DOCKER_IMAGE`: default image used by the runner
- `RUNNER_SERVICE_IMAGE`: image used by the GitLab Runner service container
- `RUNNER_SERVICE_SOURCE_IMAGE`: upstream source consumed by `scripts/prepare-runner-service-image.sh`
- `RUNNER_SERVICE_IMAGE_PREPARE_MODE`: `retag` or `build` for preparing `RUNNER_SERVICE_IMAGE`
- `RUNNER_CONTAINER_NAME`: long-running container name used by `runner-compose.yml`
- `RUNNER_REGISTRATION_CONTAINER_NAME`: temporary container name used by `runner/register-runner.sh`
- `BUILDER_IMAGE`: standard builder image tag
- `IMAGE_ARCHIVE_PATH`: offline image archive path
- `RUNNER_GPU_CONCURRENCY`: concurrency for the default GPU pool
- `RUNNER_MULTI_GPU_CONCURRENCY`: concurrency for the multi-GPU pool

Recommended practice:

- Keep `RUNNER_DOCKER_IMAGE` and `BUILDER_IMAGE` aligned
- Replace the example registry with your internal registry
- Use explicit immutable tags instead of `latest`

## 5. Build the standard CUDA builder image

Run:

```bash
scripts/build-builder-image.sh
scripts/build-builder-image.sh --platform ubuntu2204
scripts/build-builder-image.sh --all-platforms
```

The script will:

- Read `BUILDER_IMAGE` from `.env`
- Build the platform Dockerfile under `docker/cuda-builder/`
- Use `--platform <name>` to build one non-default target
- Use `--all-platforms` to build every platform listed in `BUILDER_PLATFORMS`
- Reuse Docker daemon proxy settings when available
- Automatically switch to `--network host` when the proxy points to `127.0.0.1` or `localhost`
- Pass the same proxy inputs to every builder platform; `centos7` then maps that input to `yum` internally

If the destination host is air-gapped, also run:

```bash
scripts/prepare-runner-service-image.sh
scripts/export-images.sh
```

`scripts/prepare-runner-service-image.sh` prepares `RUNNER_SERVICE_IMAGE` in an online environment before export. By default it pulls `RUNNER_SERVICE_SOURCE_IMAGE` and retags it to `RUNNER_SERVICE_IMAGE`. If you want a repo-local build entry point instead, run:

```bash
scripts/prepare-runner-service-image.sh --mode build
```

Then `scripts/export-images.sh` exports all builder tags derived from `BUILDER_IMAGE_FAMILY` and `BUILDER_PLATFORMS`, plus `RUNNER_DOCKER_IMAGE` and `RUNNER_SERVICE_IMAGE`, into the archive configured by `IMAGE_ARCHIVE_PATH`. After copying that archive to the target host, run:

```bash
scripts/import-images.sh
```

to load the deployment images in one step.

The export also writes `${IMAGE_ARCHIVE_PATH}.sha256`. `scripts/import-images.sh` verifies that hash by default before loading the archive. Use `--skip-hash-check` only if you intentionally want to bypass integrity checking.

An offline host can only run `scripts/runner-compose.sh up -d` after `RUNNER_SERVICE_IMAGE` has been imported into the local Docker daemon. `runner-compose.yml` only consumes that image; it does not build it on the offline host.

For a complete connected-host to offline-host workflow, use this order:

1. Connected host:
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

If the offline host keeps a full checkout of this repository, export and import the operator toolkit first:

```bash
scripts/export-project-bundle.sh --mode assets --output artifacts/project-operator-toolkit.tar.gz
scripts/import-project-bundle.sh --mode assets --input artifacts/project-operator-toolkit.tar.gz --target-dir /path/to/project
```

If the offline host does not keep a repository checkout, export the same toolkit archive and unpack it manually:

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

If another project outside this repository needs the same images and integration assets, run:

```bash
scripts/export-project-bundle.sh
scripts/import-project-bundle.sh --target-dir /path/to/other/project
```

The imported files land in `/path/to/other/project/.gpu-devops/` by default.

The importer also generates `/path/to/other/project/.gpu-devops/.env`, which makes the copied `compose.sh` use the target project root as `HOST_PROJECT_DIR` and `CUDA_CXX_PROJECT_DIR=.`

That imported `.gpu-devops/` directory is now a reusable operator toolkit. Besides the local build wrappers, it also includes image import/export, Runner service image preparation, builder Dockerfiles plus bundled deps, and Runner registration assets.

If you only need one side of that bundle flow, use `--mode`:

```bash
scripts/export-project-bundle.sh --mode images
scripts/import-project-bundle.sh --mode images --input artifacts/project-integration-bundle.tar.gz

scripts/export-project-bundle.sh --mode assets
scripts/import-project-bundle.sh --mode assets --target-dir /path/to/other/project
```

Each exported project bundle also produces a sibling `.sha256` file. The importer verifies that file by default before unpacking, and in `all` or `images` mode it also verifies the nested `images/offline-images.tar.gz`. Use `--skip-hash-check` only when you explicitly need to bypass those checks.

The image includes:

- `nvcc`
- `cmake 3.26.0`
- `ninja`
- `gcc/g++`
- `Eigen3 3.4.0`
- `OpenMPI 4.1.6` built as static libraries with C/C++ wrappers
- `Project Chrono` at commit `3eb56218b`
- `HDF5 1.14.1-2` with zlib compression support
- `h5engine-sph` rebuilt against `${HOME}/deps/hdf5-install`
- `h5engine-dem` rebuilt against `${HOME}/deps/hdf5-install`
- `muparserx` from the `master` branch
- `git`
- `gdb`
- `python3`
- `pip`
- `conan`

After build, verify tool versions:

```bash
docker run --rm "${BUILDER_IMAGE}" nvcc --version
docker run --rm "${BUILDER_IMAGE}" cmake --version
docker run --rm "${BUILDER_IMAGE}" conan --version
docker run --rm "${BUILDER_IMAGE}" sh -lc 'mpicc --showme:version && mpicxx --showme:command && test -f /opt/openmpi/lib/libmpi.a && test ! -e /opt/openmpi/lib/libmpi.so && test -f /usr/local/include/eigen3/Eigen/Core && test -f "${HOME}/deps/chrono-install/lib/libChronoEngine.so" && ldd "${HOME}/deps/chrono-install/lib/libChronoEngine.so"'
docker run --rm "${BUILDER_IMAGE}" sh -lc 'test -f "${HOME}/deps/hdf5-install/lib/libhdf5.so" && ldd "${HOME}/deps/hdf5-install/lib/libhdf5.so" && "${HOME}/deps/hdf5-install/bin/h5cc" -showconfig >/dev/null'
docker run --rm "${BUILDER_IMAGE}" sh -lc 'test -f "${HOME}/deps/h5engine-sph/build/h5Engine/libh5Engine.so" && ldd "${HOME}/deps/h5engine-sph/build/h5Engine/libh5Engine.so" && "${HOME}/deps/h5engine-sph/build/testHdf5"'
docker run --rm "${BUILDER_IMAGE}" sh -lc 'test -f "${HOME}/deps/h5engine-dem/build/h5Engine/libh5Engine.so" && ldd "${HOME}/deps/h5engine-dem/build/h5Engine/libh5Engine.so" && "${HOME}/deps/h5engine-dem/build/testHdf5"'
docker run --rm "${BUILDER_IMAGE}" sh -lc 'cd "${HOME}/deps/muparserx" && git rev-parse --abbrev-ref HEAD && test -f build/libmuparserx.so && ldd build/libmuparserx.so && find "${HOME}/deps/muparserx-install/lib" -maxdepth 1 -name "libmuparserx.so*" | grep -q .'
```

Expected:

- `nvcc` reports `release 11.7`
- `cmake` reports `3.26.0`
- `conan` reports a valid version
- `mpicc` reports `Open MPI 4.1.6`
- `mpicxx` resolves to the C++ compiler wrapper
- `Eigen/Core` exists under `/usr/local/include/eigen3`
- OpenMPI is installed as static libraries only under `/opt/openmpi/lib`
- Chrono is installed under `${HOME}/deps/chrono-install`
- `ldd ${HOME}/deps/chrono-install/lib/libChronoEngine.so` does not show dynamic `libstdc++.so` or `libgcc_s.so`
- HDF5 is installed under `${HOME}/deps/hdf5-install`
- `ldd ${HOME}/deps/hdf5-install/lib/libhdf5.so` shows a `libz.so` dependency and `${HOME}/deps/hdf5-install/bin/h5cc -showconfig` succeeds
- `h5engine-sph` is installed under `${HOME}/deps/h5engine-sph`
- `h5engine-dem` is installed under `${HOME}/deps/h5engine-dem`
- each `ldd ${HOME}/deps/h5engine-*/build/h5Engine/libh5Engine.so` resolves the package-local `third/hdf5/lib/linux/libhdf5.so`
- each `${HOME}/deps/h5engine-*/build/testHdf5` succeeds
- `muparserx` is cloned under `${HOME}/deps/muparserx`
- `muparserx` stays on branch `master`
- `ldd ${HOME}/deps/muparserx/build/libmuparserx.so` succeeds
- `${HOME}/deps/muparserx-install/lib/libmuparserx.so*` exists

## 6. Start the GitLab Runner service

Run:

```bash
scripts/runner-compose.sh up -d
scripts/runner-compose.sh ps
```

The wrapper script automatically uses:

- `docker compose`
- or `docker-compose`

The repository now has two Compose entry points:

- `scripts/runner-compose.sh` for the GitLab Runner service in `runner-compose.yml`
- `scripts/compose.sh` for local CUDA/C++ project builds in `docker-compose.yml`

Example local builds:

```bash
scripts/compose.sh run --rm cuda-cxx-centos7
scripts/compose.sh up --abort-on-container-exit cuda-cxx-centos7 cuda-cxx-ubuntu2204
```

The current host directory is mounted to `/workspace`. `CUDA_CXX_PROJECT_DIR` selects the source tree inside that workspace, and `CUDA_CXX_BUILD_ROOT` stores output per platform.

For a ready-made `.env` example with custom `CUDA_CXX_CMAKE_ARGS` and `CUDA_CXX_BUILD_ARGS`, see [cuda-cxx.env.example](/home/joe/repo/gpu-devops/examples/env/cuda-cxx.env.example).

The main runner container image is `RUNNER_SERVICE_IMAGE`, which should already exist locally before you start `runner-compose.yml` on an offline host.

You can inspect logs with:

```bash
docker logs gitlab-runner
```

Expected:

- the container starts normally
- the mounted config and cache directories are available
- there are no obvious startup or mount errors

## 7. Register shared runners

The platform provides two runner pools.

### 7.1 Default GPU pool

For single-GPU build jobs:

```bash
runner/register-runner.sh gpu
```

Default tags:

- `gpu`
- `cuda`
- `cuda-11`

### 7.2 Multi-GPU pool

For jobs that need more than one GPU visible:

```bash
runner/register-runner.sh multi
```

Default tags:

- `gpu-multi`
- `cuda`
- `cuda-11`

After registration, GitLab should show two shared runners:

- one for standard GPU jobs
- one for multi-GPU jobs

## 8. How projects consume the shared platform

Projects do not manage runners themselves. They only need to:

1. reference the standard builder image
2. use the correct runner tags
3. run their own build commands

Minimal example:

```yaml
default:
  image: tf-particles/devops/cuda-builder:cuda11.7-cmake3.26-centos7
  tags:
    - gpu
    - cuda
    - cuda-11
```

Change the image suffix to `rocky8` or `ubuntu2204` when your project needs one of the other published builder variants.

Full example:

- [examples/gitlab-ci/shared-gpu-runner.yml](/home/joe/repo/gpu-devops/examples/gitlab-ci/shared-gpu-runner.yml)

### 8.1 Single-GPU job example

```yaml
gpu-smoke:
  stage: verify
  tags:
    - gpu
    - cuda
    - cuda-11
  script:
    - nvidia-smi
    - nvcc --version
    - cmake --version
```

### 8.2 Multi-GPU job example

```yaml
multi-gpu-smoke:
  stage: verify
  tags:
    - gpu-multi
    - cuda
    - cuda-11
  variables:
    GPU_COUNT: "2"
  script:
    - echo "Requested GPU count: ${GPU_COUNT}"
    - nvidia-smi
```

Important note:

- In v1, multi-GPU scheduling is implemented through a separate runner pool, not exact GPU reservation by the GitLab scheduler
- Project-specific dependencies should be installed in the project pipeline, or in a project-derived image built on top of the platform base image

## 9. Minimal CUDA/CMake example

The repository includes a minimal CUDA example:

- [examples/cuda-smoke/CMakeLists.txt](/home/joe/repo/gpu-devops/examples/cuda-smoke/CMakeLists.txt)
- [examples/cuda-smoke/main.cu](/home/joe/repo/gpu-devops/examples/cuda-smoke/main.cu)

Inside CI, the build can run as:

```bash
cmake -S examples/cuda-smoke -B build -G Ninja
cmake --build build
```

You can also test locally:

```bash
cmake -S examples/cuda-smoke -B /tmp/cuda-smoke-build -G "Unix Makefiles"
cmake --build /tmp/cuda-smoke-build
```

## 10. Recommended rollout sequence

Use this order for initial rollout:

1. Run `scripts/verify-host.sh`
2. Build and verify the builder image
3. Start the `gitlab-runner` container
4. Register the `gpu` runner
5. Register the `gpu-multi` runner
6. Run the sample CI config in a test project
7. After the smoke pipeline is stable, allow business projects to adopt it

## 11. Troubleshooting

### 11.1 CUDA base image cannot be pulled

Check:

- Docker daemon registry configuration
- proxy configuration
- whether Docker daemon needs a restart
- whether this command works:

```bash
docker pull nvidia/cuda:11.7.1-devel-centos7
docker pull nvidia/cuda:11.7.1-devel-rockylinux8
docker pull nvidia/cuda:11.7.1-devel-ubuntu22.04
```

### 11.1.1 CentOS 7 note

CentOS 7 is end-of-life, so the default `mirrorlist.centos.org` flow is no longer reliable. The current Dockerfile automatically rewrites the base YUM repositories to `vault.centos.org` during build.

If your environment provides an internal YUM mirror, it is better to switch to that mirror later instead of depending on the public CentOS vault.

### 11.1.2 CentOS 7 compatibility guidance

CentOS 7 can satisfy the current CUDA 11.7 + CMake 3.26 platform target, but it is not a good long-term evolution baseline. You should decide explicitly in a later platform iteration:

- whether CentOS 7 compatibility still matters
- whether to migrate to Rocky Linux or AlmaLinux
- whether to migrate to a supported Ubuntu LTS base

If future requirements need newer Python, OpenSSL, or Conan ecosystems, CentOS 7 will become increasingly expensive to maintain.
```

### 11.2 Build hangs while downloading CMake

This repository downloads the CMake installer from GitHub Releases. If it hangs, check:

- whether the build container can reach GitHub
- whether your proxy only listens on `127.0.0.1`
- whether `scripts/build-builder-image.sh` is up to date and includes proxy propagation plus `--network host` fallback

### 11.3 Container says GPU is not available

If you only run:

```bash
docker run --rm "${BUILDER_IMAGE}" nvcc --version
```

the warning about missing NVIDIA driver is expected, because that command does not enable GPU runtime.

To validate GPU visibility, run a real GPU test in CI:

```bash
nvidia-smi
```

or test manually:

```bash
docker run --rm --gpus all "${BUILDER_IMAGE}" nvidia-smi
```

### 11.4 Runner is registered but jobs do not start

Check:

- job tags exactly match runner tags
- the runner is shared
- `RUNNER_RUN_UNTAGGED` behavior matches your policy
- the project is allowed to use shared runners

### 11.5 `scripts/verify-host.sh` stops at the NVIDIA Container Toolkit runtime check

If `scripts/verify-host.sh` stops at:

```text
[4/5] Checking NVIDIA Container Toolkit runtime
```

or if this command:

```bash
docker run --rm --gpus all nvidia/cuda:12.4.1-base-ubuntu22.04 nvidia-smi
```

fails with:

```text
could not select device driver "" with capabilities: [[gpu]]
```

the problem is usually not the driver itself. It usually means Docker has not been wired to `nvidia-container-toolkit` yet. For this repository, that is not optional because:

- `scripts/verify-host.sh` expects `docker info` to expose the `nvidia` runtime
- `runner/register-runner.sh` registers the runner with `--docker-runtime nvidia`
- `runner/config.template.toml` also sets `runtime = "nvidia"`

Check:

```bash
docker info --format '{{json .Runtimes}}'
command -v nvidia-ctk
command -v nvidia-container-cli
```

If the `nvidia` runtime is missing, install `nvidia-container-toolkit` and run:

```bash
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
```

Then verify again:

```bash
docker run --rm --gpus all nvidia/cuda:12.4.1-base-ubuntu22.04 nvidia-smi
scripts/verify-host.sh
```

### 11.6 Offline `nvidia-container-toolkit` install shows an `_apt` permission warning

If you install local `.deb` files like this:

```bash
sudo apt install -y ./*.deb
```

and see a message like:

```text
Download is performed unsandboxed as root ... couldn't be accessed by user '_apt'
```

that is usually only a directory permission warning. It does not automatically mean the install failed. The real failures to watch for are:

- `Unable to correct problems`
- `unmet dependencies`
- `dpkg returned an error code`

The safer approach is to place the offline packages in a directory readable by `_apt`, for example:

```bash
mkdir -p /tmp/offline-nvidia-toolkit
cp ~/offline-nvidia-toolkit/*.deb /tmp/offline-nvidia-toolkit/
chmod 755 /tmp/offline-nvidia-toolkit
chmod 644 /tmp/offline-nvidia-toolkit/*.deb
cd /tmp/offline-nvidia-toolkit
sudo apt install -y ./*.deb
```

### 11.7 The online host is Ubuntu 22.04 but the offline host is Ubuntu 20.04

The most reliable approach is not to mix `ubuntu2004` packages directly on the `ubuntu2204` host. Instead, run an `ubuntu:20.04` container on the online machine and collect the offline `.deb` packages there.

On the connected host:

```bash
mkdir -p ~/offline-nvidia-toolkit-ubuntu2004
docker run --rm -it \
  -v ~/offline-nvidia-toolkit-ubuntu2004:/out \
  ubuntu:20.04 bash
```

Inside that container:

```bash
apt-get update
apt-get install -y curl gnupg ca-certificates

curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
  gpg --dearmor --yes -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

curl -fsSL https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
  sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
  > /etc/apt/sources.list.d/nvidia-container-toolkit.list

apt-get update
apt-get install --download-only -y nvidia-container-toolkit
cp /var/cache/apt/archives/*.deb /out/
```

Back on the online host, package the collected files:

```bash
cd ~/offline-nvidia-toolkit-ubuntu2004
tar -czf nvidia-container-toolkit-ubuntu2004-offline.tar.gz ./*.deb
```

Copy that archive to the Ubuntu 20.04 offline host, install the `.deb` packages there, then continue with:

```bash
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
docker run --rm --gpus all nvidia/cuda:12.4.1-base-ubuntu20.04 nvidia-smi
```

## 12. Reference documents

- [docs/operations.md](/home/joe/repo/gpu-devops/docs/operations.md)
- [docs/self-check.md](/home/joe/repo/gpu-devops/docs/self-check.md)
- [docs/platform-contract.md](/home/joe/repo/gpu-devops/docs/platform-contract.md)
