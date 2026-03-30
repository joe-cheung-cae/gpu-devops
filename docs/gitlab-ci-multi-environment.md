# GitLab CI Organization for Three Linux Builder Images

This guide explains the recommended GitLab CI layout when one project should build on the three published Linux builder images provided by this platform:

- `centos7`
- `rocky8`
- `ubuntu2204`

That three-platform Docker matrix should be the default pipeline shape. It gives one pipeline run three compatibility checks at the same time, using the current published builder family:

- `${BUILDER_IMAGE_FAMILY}-centos7`
- `${BUILDER_IMAGE_FAMILY}-rocky8`
- `${BUILDER_IMAGE_FAMILY}-ubuntu2204`

Windows and Linux shell runners are still valid extensions, but they should come after the Docker matrix is already in place.

## Recommended structure

Use one root pipeline file, one shared policy file, and one Docker matrix file:

```text
.gitlab-ci.yml
.gitlab/ci/common.yml
.gitlab/ci/docker-linux-matrix.yml
.gitlab/ci/windows.yml
.gitlab/ci/linux-shell.yml
scripts/ci/build-linux.sh
scripts/ci/build-windows.ps1
```

Recommended responsibility split:

- `.gitlab-ci.yml`: stages and `include`
- `common.yml`: shared variables, artifacts, and rules
- `docker-linux-matrix.yml`: the default three-platform Linux builder matrix
- `windows.yml`: optional Windows jobs
- `linux-shell.yml`: optional non-Docker Linux shell jobs
- `scripts/ci/*`: the actual build logic so YAML stays compact

## Recommended pipeline flow

For projects that target the current platform images, the most useful pipeline flow is:

1. verify the shared CUDA toolchain on the builder image
2. build the project on `centos7`, `rocky8`, and `ubuntu2204`
3. optionally run platform-specific tests on the same matrix
4. package only after all three builds finish successfully

This flow catches compatibility regressions early. It is especially useful when one project must keep supporting a legacy baseline like `centos7` while also validating newer Linux environments such as `rocky8` and `ubuntu2204`.

## Root pipeline example

Keep the root file small and let it assemble environment-specific pieces:

```yaml
stages:
  - verify
  - build
  - test
  - package

include:
  - local: .gitlab/ci/common.yml
  - local: .gitlab/ci/docker-linux-matrix.yml
  - local: .gitlab/ci/windows.yml
  - local: .gitlab/ci/linux-shell.yml
```

The Docker Linux matrix is the primary path. The Windows and Linux shell includes are optional extensions.

## Common template example

Put shared policy in one hidden template file:

```yaml
default:
  interruptible: true

variables:
  BUILDER_IMAGE_FAMILY: tf-particles/devops/cuda-builder:cuda11.7-cmake3.26
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
      - build-*/
```

This is the right place for branch rules, retry policy, common variables, and artifact retention.

## Recommended Docker Linux matrix

Use GitLab `parallel:matrix` so one job definition expands into the three supported Linux builder variants:

```yaml
.docker_linux_base:
  tags:
    - gpu
    - cuda
    - cuda-11
  extends:
    - .workflow_rules
    - .build_artifacts

docker:verify:
  extends: .docker_linux_base
  stage: verify
  image: ${BUILDER_IMAGE_FAMILY}-centos7
  script:
    - nvidia-smi
    - nvcc --version
    - cmake --version

docker:build:
  extends: .docker_linux_base
  stage: build
  parallel:
    matrix:
      - BUILD_PLATFORM: [centos7, rocky8, ubuntu2204]
  image: ${BUILDER_IMAGE_FAMILY}-${BUILD_PLATFORM}
  script:
    - bash scripts/ci/build-linux.sh "build-${BUILD_PLATFORM}"
  artifacts:
    when: always
    expire_in: 7 days
    paths:
      - build-${BUILD_PLATFORM}/
```

This layout is the recommended default because:

- the job log clearly shows the platform through `BUILD_PLATFORM`
- the image is resolved directly from the published builder family
- build output is isolated as `build-centos7`, `build-rocky8`, and `build-ubuntu2204`
- all three platforms stay in sync without copying the same YAML three times

## Example build script

Use one Linux build script and make the build directory explicit from the job:

```bash
#!/usr/bin/env bash
set -euo pipefail

BUILD_DIR="${1:?missing build dir}"

cmake -S . -B "${BUILD_DIR}" -G Ninja -DCMAKE_BUILD_TYPE="${CMAKE_BUILD_TYPE:-Release}"
cmake --build "${BUILD_DIR}" --parallel
```

This keeps platform differences in the image selection, not in duplicated inline shell blocks.

## Example test and package stages

Once the three build jobs are in place, later stages should depend on the matrix output instead of rebuilding everything again.

Example pattern:

```yaml
docker:test:
  extends: .docker_linux_base
  stage: test
  parallel:
    matrix:
      - BUILD_PLATFORM: [centos7, rocky8, ubuntu2204]
  image: ${BUILDER_IMAGE_FAMILY}-${BUILD_PLATFORM}
  script:
    - ctest --test-dir "build-${BUILD_PLATFORM}" --output-on-failure

package:
  extends: .workflow_rules
  stage: package
  needs:
    - job: docker:build
  script:
    - echo "package after all Linux builds succeed"
```

The exact `needs` shape may vary by project, but the important rule is the same: package only after the three Linux builds are green.

## Matrix vs explicit jobs

For this repository’s current Linux image set, prefer `parallel:matrix` by default.

Use `parallel:matrix` when:

- the three platforms run the same build steps
- only the image tag and build output directory differ
- you want compact YAML and a clear platform matrix

Use explicit jobs only when:

- one platform needs a meaningfully different script
- one platform needs special variables, caches, or timeouts
- the team wants per-platform job names such as `build:centos7` for operational reasons

If the behavior is still mostly identical, matrix is the better choice.

## Extensions

After the three-platform Docker path is stable, you can layer in other environments.

### Linux shell runner extension

For a physical Linux machine or shell executor:

```yaml
.linux_shell_base:
  tags:
    - linux-shell
  extends:
    - .workflow_rules
    - .build_artifacts

linux-shell:build:
  extends: .linux_shell_base
  stage: build
  script:
    - bash scripts/ci/build-linux.sh build-linux-shell
```

This is useful for comparing Docker-based builds with a host-native Linux environment, but it should not replace the three-platform builder matrix.

### Windows runner extension

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

windows:build:
  extends: .windows_base
  stage: build
  script:
    - powershell -NoProfile -ExecutionPolicy Bypass -File scripts/ci/build-windows.ps1 -BuildDir build-win
```

Keep Windows-specific generators and path handling inside the Windows path instead of trying to force Linux and Windows into one shared inline script.

## Practical recommendation

If your project is built on this platform today, start with:

- one `docker:verify` job on `centos7`
- one `docker:build` matrix for `centos7`, `rocky8`, `ubuntu2204`
- optional `docker:test` matrix on the same three platforms
- one package stage after the Linux matrix completes

Only add Windows or Linux shell jobs when they solve a real project need beyond the three published Linux builder images.
