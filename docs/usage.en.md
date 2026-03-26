# Project Usage Guide

This guide is a quick step-by-step reference for the two main ways to use this repository:

- platform operators who deploy and register the shared GitLab GPU Runner
- R&D engineers who build CUDA/CMake projects with the published builder image or local Compose workflow

## 1. Platform operator workflow

### Step 1: Prepare the host

```bash
cp .env.example .env
scripts/verify-host.sh
```

Then edit `.env` and set at least:

- `GITLAB_URL`
- `RUNNER_REGISTRATION_TOKEN`
- `BUILDER_IMAGE_FAMILY`
- `BUILDER_IMAGE`
- `RUNNER_DOCKER_IMAGE`

### Step 2: Build the builder image

Build the default platform:

```bash
scripts/build-builder-image.sh
```

Build a specific platform:

```bash
scripts/build-builder-image.sh --platform ubuntu2204
```

Build all supported platforms:

```bash
scripts/build-builder-image.sh --all-platforms
```

### Step 3: Start the Runner service

```bash
scripts/runner-compose.sh up -d
scripts/runner-compose.sh ps
```

The expected result is one healthy `gitlab-runner` container.

### Step 4: Register runners in GitLab

Register the default single-GPU pool:

```bash
runner/register-runner.sh gpu
```

Register the multi-GPU pool:

```bash
runner/register-runner.sh multi
```

Default tags are:

- single GPU: `gpu`, `cuda`, `cuda-11`
- multi GPU: `gpu-multi`, `cuda`, `cuda-11`

### Step 5: Validate the platform

```bash
scripts/compose.sh run --rm cuda-cxx-centos7
```

Then use [examples/gitlab-ci/shared-gpu-runner.yml](/home/joe/repo/gpu-devops/examples/gitlab-ci/shared-gpu-runner.yml) in a test project and confirm that `gpu-smoke`, `cuda-cmake-build`, and `multi-gpu-smoke` succeed.

## 2. R&D engineer workflow

### Option A: Build a project locally with Docker Compose

Point `.env` at your project tree:

- `HOST_PROJECT_DIR=/path/to/your/project`
- `CUDA_CXX_PROJECT_DIR=.`
- `CUDA_CXX_BUILD_ROOT=./artifacts/cuda-cxx-build`

Run a single-platform build:

```bash
scripts/compose.sh run --rm cuda-cxx-centos7
```

Run multiple platform builds:

```bash
scripts/compose.sh up --abort-on-container-exit cuda-cxx-centos7 cuda-cxx-ubuntu2204
```

Build outputs are written under `${CUDA_CXX_BUILD_ROOT}/<platform>`.

### Option B: Use the shared Runner in `.gitlab-ci.yml`

Start from [examples/gitlab-ci/shared-gpu-runner.yml](/home/joe/repo/gpu-devops/examples/gitlab-ci/shared-gpu-runner.yml).

If the same project also needs Linux physical-machine jobs or Windows jobs, see the mixed-runner organization guide: [gitlab-ci-multi-environment.md](/home/joe/repo/gpu-devops/docs/gitlab-ci-multi-environment.md).

Use the published builder image:

```yaml
default:
  image: tf-particles/devops/cuda-builder:cuda11.7-cmake3.26-centos7
  tags:
    - gpu
    - cuda
    - cuda-11
```

Switch the image suffix to `rocky8` or `ubuntu2204` if your project depends on that platform baseline.

### Option C: Import the integration bundle into another project

From this repository:

```bash
scripts/export-project-bundle.sh
scripts/import-project-bundle.sh --target-dir /path/to/other/project
```

The target project receives `.gpu-devops/` with the Compose files, wrapper scripts, docs, example CI config, and a generated `.env`.

If you only want images or only want files, use:

```bash
scripts/export-project-bundle.sh --mode images
scripts/import-project-bundle.sh --mode images --input artifacts/project-integration-bundle.tar.gz

scripts/export-project-bundle.sh --mode assets
scripts/import-project-bundle.sh --mode assets --target-dir /path/to/other/project
```

Both image bundles and project bundles now generate a sibling `.sha256` file. The import scripts verify that hash by default before loading or unpacking the bundle. Use `--skip-hash-check` only when you intentionally want to bypass integrity checking.
