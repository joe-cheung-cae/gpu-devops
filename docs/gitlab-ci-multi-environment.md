# GitLab CI Organization for Mixed Docker, Linux, and Windows Runners

This guide explains how to organize `.gitlab-ci.yml` when one project needs to support multiple execution environments at the same time:

- Docker-based CUDA jobs on the shared GPU runner platform
- Linux physical-machine builds
- Windows physical-machine builds

The goal is to keep the pipeline maintainable. The main `.gitlab-ci.yml` should orchestrate the pipeline, while environment-specific job definitions live in separate included files.

## Recommended structure

Use one root pipeline file plus one file per execution environment:

```text
.gitlab-ci.yml
.gitlab/ci/common.yml
.gitlab/ci/docker.yml
.gitlab/ci/linux-shell.yml
.gitlab/ci/windows.yml
scripts/ci/build-linux.sh
scripts/ci/build-windows.ps1
```

Recommended responsibility split:

- `.gitlab-ci.yml`: stages and `include`
- `common.yml`: shared variables, artifacts, and rules
- `docker.yml`: jobs that run on the shared Docker GPU runner
- `linux-shell.yml`: jobs that run on a Linux physical machine or shell runner
- `windows.yml`: jobs that run on a Windows runner
- `scripts/ci/*`: the actual build logic, so YAML stays small and readable

## Root pipeline example

Keep the root file minimal:

```yaml
stages:
  - verify
  - build
  - test
  - package

include:
  - local: .gitlab/ci/common.yml
  - local: .gitlab/ci/docker.yml
  - local: .gitlab/ci/linux-shell.yml
  - local: .gitlab/ci/windows.yml
```

This makes the pipeline easy to extend. You can add `test.yml`, `package.yml`, or release-specific includes later without turning one file into a large conditional matrix.

## Common template example

Put shared pipeline policy in one hidden job file:

```yaml
default:
  interruptible: true

variables:
  CMAKE_BUILD_TYPE: Release

.workflow_rules:
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
    - if: $CI_COMMIT_BRANCH

.build_artifacts:
  artifacts:
    when: always
    expire_in: 7 days
    paths:
      - build*/
```

This is the right place for branch rules, artifact retention, retry policy, and common variables.

## Docker runner example

Use the shared builder image and runner tags from this platform:

```yaml
.docker_cuda_base:
  image: tf-particles/devops/cuda-builder:cuda11.7-cmake3.26-centos7
  tags:
    - gpu
    - cuda
    - cuda-11
  extends:
    - .workflow_rules
    - .build_artifacts

docker:verify:
  extends: .docker_cuda_base
  stage: verify
  script:
    - nvidia-smi
    - nvcc --version
    - cmake --version

docker:build:
  extends: .docker_cuda_base
  stage: build
  script:
    - bash scripts/ci/build-linux.sh build-docker
```

Switch the image suffix to `rocky8` or `ubuntu2204` if the project depends on a different builder platform baseline.

## Linux physical-machine example

For a shell runner on a Linux build machine:

```yaml
.linux_shell_base:
  tags:
    - linux-shell
  extends:
    - .workflow_rules
    - .build_artifacts

linux:verify:
  extends: .linux_shell_base
  stage: verify
  script:
    - uname -a
    - cmake --version
    - gcc --version

linux:build:
  extends: .linux_shell_base
  stage: build
  script:
    - bash scripts/ci/build-linux.sh build-linux
```

The important pattern is to let tags choose the runner, rather than putting platform-detection logic inside one job.

## Windows physical-machine example

For a Windows runner:

```yaml
.windows_base:
  tags:
    - windows
  extends:
    - .workflow_rules
  artifacts:
    when: always
    expire_in: 7 days
    paths:
      - build-win/

windows:verify:
  extends: .windows_base
  stage: verify
  script:
    - powershell -NoProfile -ExecutionPolicy Bypass -Command "$PSVersionTable.PSVersion"
    - powershell -NoProfile -ExecutionPolicy Bypass -Command "cmake --version"

windows:build:
  extends: .windows_base
  stage: build
  script:
    - powershell -NoProfile -ExecutionPolicy Bypass -File scripts/ci/build-windows.ps1 -BuildDir build-win
```

Windows-specific generator and toolchain settings should stay in the Windows path. Do not force Windows and Linux jobs to share one giant inline script.

## Build script examples

Example Linux build script:

```bash
#!/usr/bin/env bash
set -euo pipefail

BUILD_DIR="${1:-build}"

cmake -S . -B "${BUILD_DIR}" -G Ninja -DCMAKE_BUILD_TYPE="${CMAKE_BUILD_TYPE:-Release}"
cmake --build "${BUILD_DIR}" --parallel
```

Example Windows build script:

```powershell
param(
  [string]$BuildDir = "build-win"
)

$ErrorActionPreference = "Stop"

cmake -S . -B $BuildDir -G "Visual Studio 17 2022" -DCMAKE_BUILD_TYPE=Release
cmake --build $BuildDir --config Release
```

## Recommended organization principles

- Keep the root `.gitlab-ci.yml` small.
- Split by execution environment, not by random job count.
- Use hidden jobs such as `.docker_cuda_base` and `.windows_base` for inheritance.
- Use `tags` to bind jobs to the correct runner type.
- Put the actual build logic in scripts instead of duplicating long shell blocks across YAML files.
- Let Windows, Linux shell, and Docker jobs differ where they should differ, especially generator, shell, compiler, and path handling.

## When to extend further

As the project grows, the same pattern scales well:

- add `.gitlab/ci/test.yml`
- add `.gitlab/ci/package.yml`
- add `rules` to limit expensive Windows jobs to selected branches
- add `needs` to connect package or release jobs to the right build jobs

The key idea is simple:

Do not maintain one giant environment-aware YAML file. Maintain one small orchestrator and several environment-specific templates.
