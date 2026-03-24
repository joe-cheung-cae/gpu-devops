# GitLab GPU Runner Tutorial

This document is written for two audiences:

- Platform operators who build the CUDA image, deploy GitLab Runner, and register shared runners
- Project developers who consume the shared runner platform from their own `.gitlab-ci.yml`

The current repository targets a single Docker host with NVIDIA GPUs and shared usage across multiple CUDA/CMake projects.

## 1. What the platform provides

The platform includes:

- A standard CUDA builder image: `cuda11.7-cmake3.26-centos7`
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
   - CentOS Vault or an internal YUM mirror
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

## 3.1 CentOS 7 baseline notes

The current builder image is based on `nvidia/cuda:11.7.1-devel-centos7`, which introduces a few practical constraints:

- CentOS 7 is already end-of-life, so its default public mirrors are not reliable
- The Dockerfile rewrites both the base YUM repositories and the SCLo repositories to `vault.centos.org`
- Python 3 is not sourced from the default CentOS 7 base packages; it is provided through `rh-python38`
- `conan` must stay compatible with the older OpenSSL stack, so the image explicitly constrains `urllib3<2`

If your organization provides an internal RPM/YUM mirror, it is better to replace the public vault URLs with the internal mirror later.

## 4. Configure environment variables

Create a local `.env` file:

```bash
cp .env.example .env
```

Then update the main fields:

- `GITLAB_URL`: GitLab base URL
- `RUNNER_REGISTRATION_TOKEN`: runner registration token
- `RUNNER_DOCKER_IMAGE`: default image used by the runner
- `RUNNER_SERVICE_IMAGE`: image used by the GitLab Runner service container
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
```

The script will:

- Read `BUILDER_IMAGE` from `.env`
- Build `docker/cuda-builder/Dockerfile`
- Reuse Docker daemon proxy settings when available
- Automatically switch to `--network host` when the proxy points to `127.0.0.1` or `localhost`

If the destination host is air-gapped, also run:

```bash
scripts/export-images.sh
```

This exports `BUILDER_IMAGE`, `RUNNER_DOCKER_IMAGE`, and `RUNNER_SERVICE_IMAGE` into the archive configured by `IMAGE_ARCHIVE_PATH`. After copying that archive to the target host, run:

```bash
scripts/import-images.sh
```

to load the deployment images in one step.

The image includes:

- `nvcc`
- `cmake 3.26.0`
- `ninja`
- `gcc/g++`
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
```

Expected:

- `nvcc` reports `release 11.7`
- `cmake` reports `3.26.0`
- `conan` reports a valid version

## 6. Start the GitLab Runner service

Run:

```bash
scripts/compose.sh up -d
scripts/compose.sh ps
```

The wrapper script automatically uses:

- `docker compose`
- or `docker-compose`

The main runner container image is:

- `gitlab/gitlab-runner:alpine-v16.10.1`

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
  image: registry.example.com/devops/cuda-builder:cuda11.7-cmake3.26-centos7
  tags:
    - gpu
    - cuda
    - cuda-11
```

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

## 12. Reference documents

- [docs/operations.md](/home/joe/repo/gpu-devops/docs/operations.md)
- [docs/self-check.md](/home/joe/repo/gpu-devops/docs/self-check.md)
- [docs/platform-contract.md](/home/joe/repo/gpu-devops/docs/platform-contract.md)
