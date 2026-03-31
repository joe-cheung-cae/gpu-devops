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
- `RUNNER_TLS_CA_FILE` when GitLab HTTPS uses a self-signed certificate

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

### Step 3: Prepare the Runner service image and offline bundle

In a connected environment, prepare the Runner service image before export:

```bash
scripts/prepare-runner-service-image.sh
scripts/export-images.sh
```

This produces:

- `artifacts/offline-images.tar.gz`
- `artifacts/offline-images.tar.gz.images.txt`
- `artifacts/offline-images.tar.gz.sha256`

Selective export examples:

```bash
scripts/export-images.sh --only-runner-service --output artifacts/offline-runner-service.tar.gz
scripts/export-images.sh --only-build-images --output artifacts/offline-build-images.tar.gz
```

`--only-runner-service` exports only `RUNNER_SERVICE_IMAGE`. `--only-build-images` exports only the builder image matrix.

If the offline host does not keep a full clone of this repository, also export the operator toolkit:

```bash
scripts/export-project-bundle.sh --mode assets --output artifacts/project-operator-toolkit.tar.gz
```

### Step 4: Import assets on the offline host

If the offline host still has a checkout of this repository, import the operator toolkit first:

```bash
scripts/import-project-bundle.sh --mode assets --input artifacts/project-operator-toolkit.tar.gz --target-dir /path/to/project
```

If the offline host does not have a repository checkout, unpack the toolkit archive manually:

```bash
mkdir -p /path/to/project/.gpu-devops
tmpdir="$(mktemp -d)"
tar -xzf artifacts/project-operator-toolkit.tar.gz -C "${tmpdir}"
cp -R "${tmpdir}/assets/." /path/to/project/.gpu-devops/
```

Then create `.gpu-devops/.env` from [offline-env-configuration.md](/home/joe/repo/gpu-devops/docs/offline-env-configuration.md), and import the image archive:

```bash
scripts/import-images.sh --input artifacts/offline-images.tar.gz
```

If you unpacked the toolkit manually, run:

```bash
.gpu-devops/scripts/import-images.sh --input /path/to/offline-images.tar.gz
.gpu-devops/scripts/runner-compose.sh up -d
.gpu-devops/runner/register-runner.sh gpu
.gpu-devops/runner/register-shell-runner.sh gpu
```

If you imported or unpacked the toolkit, run later commands from `/path/to/project/.gpu-devops/`.

### Step 5: Start the Runner service

```bash
scripts/runner-compose.sh up -d
scripts/runner-compose.sh ps
```

The expected result is one healthy `gitlab-runner` container.

### Step 6: Register runners in GitLab

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

If your environment must run jobs as the Linux user `gitlab-runner` through a normal shell executor, register the shell-runner path instead:

```bash
sudo -u gitlab-runner -H runner/register-shell-runner.sh gpu
sudo -u gitlab-runner -H runner/register-shell-runner.sh multi
```

That path expects:

- the `gitlab-runner` user can run Docker and `docker compose`
- the target project checkout is readable by `gitlab-runner`
- the builder images are already loaded locally
- project jobs call `.gpu-devops/scripts/compose.sh run --rm cuda-cxx-centos7`

### Step 7: Validate the platform and local build environment

```bash
scripts/compose.sh run --rm cuda-cxx-centos7
```

Then use [examples/gitlab-ci/shared-gpu-runner.yml](/home/joe/repo/gpu-devops/examples/gitlab-ci/shared-gpu-runner.yml) in a test project and confirm that `gpu-smoke`, `cuda-cmake-build`, and `multi-gpu-smoke` succeed.

For the shell-runner path, start from [examples/gitlab-ci/shared-gpu-shell-runner.yml](/home/joe/repo/gpu-devops/examples/gitlab-ci/shared-gpu-shell-runner.yml). It keeps Linux and Windows jobs side by side in one pipeline, and uses `BUILD_PLATFORM=centos7` by default for the Linux compose-driven build. That default belongs to the CI example, not `.env`. `rocky8` and `ubuntu2204` remain supported Linux alternatives.

## 2. R&D engineer workflow

### Option A: Build a project locally with Docker Compose

Point `.env` at your project tree:

- `HOST_PROJECT_DIR=/path/to/your/project`
- `CUDA_CXX_PROJECT_DIR=.`
- `CUDA_CXX_BUILD_ROOT=./artifacts/cuda-cxx-build`
- `CUDA_CXX_INSTALL_ROOT=./artifacts/cuda-cxx-install`

Run a single-platform build:

```bash
scripts/compose.sh run --rm cuda-cxx-centos7
```

Run multiple platform builds:

```bash
scripts/compose.sh up --abort-on-container-exit cuda-cxx-centos7 cuda-cxx-ubuntu2204
```

Build outputs are written under `${CUDA_CXX_BUILD_ROOT}/<platform>`, and install outputs are written under `${CUDA_CXX_INSTALL_ROOT}/<platform>`.

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

### Option C: Use a shell runner and invoke `docker compose` from the job

Start from [examples/gitlab-ci/shared-gpu-shell-runner.yml](/home/joe/repo/gpu-devops/examples/gitlab-ci/shared-gpu-shell-runner.yml).

This path is for projects whose GitLab jobs must run as the Linux user `gitlab-runner` through a normal shell executor. The job itself does not use `image:`. Instead, it calls:

```yaml
script:
  - .gpu-devops/scripts/compose.sh run --rm "cuda-cxx-${BUILD_PLATFORM}"
```

The example keeps this Linux default:

- `BUILD_PLATFORM=centos7`

Linux shell-runner builds support `centos7`, `rocky8`, and `ubuntu2204`. A separate Windows-tagged job is included in the same pipeline, so Windows and Linux jobs can run in parallel without a separate `BUILD_OS` switch.

The example also includes `test` and `deploy` stages for both Linux and Windows, so teams can extend the same shell-runner pipeline from build verification into test execution and deployment handoff.
In the Linux deploy job, `BUILD_PLATFORM` is used again to choose the platform-specific deployment shell, for example `./scripts/deploy-centos7.sh`, `./scripts/deploy-rocky8.sh`, or `./scripts/deploy-ubuntu2204.sh`.
For Linux jobs, the example keeps per-platform artifacts under `${CUDA_CXX_BUILD_ROOT}/${BUILD_PLATFORM}` and `${CUDA_CXX_INSTALL_ROOT}/${BUILD_PLATFORM}`. The build path follows the existing compose contract, and the additional install path is explicitly preserved so later `test` and `deploy` jobs can reuse it.
For offline `.env` details, including generated defaults, Docker executor, shell runner, and self-signed HTTPS GitLab setup, see [offline-env-configuration.md](/home/joe/repo/gpu-devops/docs/offline-env-configuration.md).

### Option D: Import the integration bundle into another project

From this repository:

```bash
scripts/export-project-bundle.sh
scripts/import-project-bundle.sh --target-dir /path/to/other/project
```

The target project receives `.gpu-devops/` with the Compose files, operator scripts, runner assets, Docker build assets, docs, example CI config, and a generated `.env`.

If you only want images or only want files, use:

```bash
scripts/export-project-bundle.sh --mode images
scripts/import-project-bundle.sh --mode images --input artifacts/project-integration-bundle.tar.gz

scripts/export-project-bundle.sh --mode assets
scripts/import-project-bundle.sh --mode assets --target-dir /path/to/other/project
```

Both image bundles and project bundles now generate a sibling `.sha256` file. The import scripts verify that hash by default before loading or unpacking the bundle. Use `--skip-hash-check` only when you intentionally want to bypass integrity checking.
