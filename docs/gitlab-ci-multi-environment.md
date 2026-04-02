# GitLab CI Organization for Shell Runner + Multi-Platform Builds

This guide describes a shell-runner-first CI layout when a project wants to
validate multiple Linux builder platforms plus optional Windows jobs.

The shell runner does not use GitLab's Docker executor. Instead, each job calls
`.gpu-devops/scripts/compose.sh` to run inside the selected builder image.

For a concrete starting point, use
[examples/gitlab-ci/shared-gpu-shell-runner.yml](../examples/gitlab-ci/shared-gpu-shell-runner.yml)
and adapt the Linux job matrix to your project.

## Recommended structure

Use one root pipeline file, one shared policy file, and a dedicated matrix file:

```text
.gitlab-ci.yml
.gitlab/ci/common.yml
.gitlab/ci/linux-compose-matrix.yml
.gitlab/ci/windows.yml
scripts/ci/build-linux.sh
scripts/ci/build-windows.ps1
```

Recommended responsibility split:

- `.gitlab-ci.yml`: stages and `include`
- `common.yml`: shared variables, artifacts, and rules
- `linux-compose-matrix.yml`: Linux matrix calling `compose.sh`
- `windows.yml`: optional Windows jobs
- `scripts/ci/*`: build logic so YAML stays compact

## Default matrix flow

The Linux shell-runner flow should validate all supported builder platforms
whenever possible:

- `centos7`
- `rocky8`
- `ubuntu2204`

Use a matrix variable to control the platform and pass it to the compose entry:

```yaml
stages:
  - verify
  - build
  - test

.shell_linux_base:
  tags:
    - gpu
    - cuda
    - cuda-11
  variables:
    BUILD_PLATFORM: centos7

linux:verify:
  extends: .shell_linux_base
  stage: verify
  script:
    - .gpu-devops/scripts/prepare-builder-deps.sh --platform "${BUILD_PLATFORM}"
    - .gpu-devops/scripts/compose.sh run --rm "cuda-cxx-${BUILD_PLATFORM}" nvidia-smi

linux:build:
  extends: .shell_linux_base
  stage: build
  parallel:
    matrix:
      - BUILD_PLATFORM: [centos7, rocky8, ubuntu2204]
  script:
    - .gpu-devops/scripts/prepare-builder-deps.sh --platform "${BUILD_PLATFORM}"
    - .gpu-devops/scripts/compose.sh run --rm "cuda-cxx-${BUILD_PLATFORM}" bash scripts/ci/build-linux.sh "build-${BUILD_PLATFORM}"
```

This layout keeps platform differences in the compose target name, not in
duplicated YAML blocks.

## Optional Windows jobs

Windows jobs are still useful for MSVC builds and MS-MPI validation. Put them
in a separate include file and keep them independent from the Linux matrix.

## Notes

- The shell runner must run as the `gitlab-runner` user (or your configured
  `RUNNER_SHELL_USER`) with access to Docker and `docker compose`.
- The project checkout path must be readable by the shell runner user.
- The builder images must already be present on the host (imported or built).
