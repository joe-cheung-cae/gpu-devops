# Self-check

Use this checklist after host preparation and after any Runner upgrade.

## 1. Validate the host

Run:

```bash
scripts/verify-host.sh
```

Expected:

- Docker version prints successfully
- Compose version prints successfully
- `nvidia-smi` prints the installed GPU
- Docker runtimes include `nvidia`

If this step fails because Docker does not expose the `nvidia` runtime, or because offline `nvidia-container-toolkit` installation reports `_apt` permission warnings, see the troubleshooting section in [tutorial.zh-CN.md](tutorial.zh-CN.md) or [tutorial.en.md](tutorial.en.md).

## 2. Build the standard builder image

Run:

```bash
cp .env.example .env
scripts/build-builder-image.sh
scripts/build-builder-image.sh --platform rocky8
scripts/build-builder-image.sh --all-platforms
docker run --rm "${BUILDER_IMAGE}" sh -lc 'test -f /usr/include/uuid/uuid.h && command -v ccache >/dev/null && ! command -v mpicc >/dev/null'
scripts/prepare-builder-deps.sh --platform centos7
docker run --rm -v "${PWD}:/workspace" -w /workspace "${BUILDER_IMAGE}" sh -lc 'test -f "./third_party/centos7/chrono-install/lib/libChronoEngine.so" && test -f "./third_party/centos7/eigen3-install/include/eigen3/Eigen/Core" && test -x "./third_party/centos7/openmpi-install/bin/mpicc" && test -f "./third_party/centos7/openmpi-install/lib/libmpi.so" && test -f "./third_party/centos7/hdf5-install/lib/libhdf5.so" && test -f "./third_party/centos7/h5engine-sph/build/h5Engine/libh5Engine.so" && test -f "./third_party/centos7/h5engine-dem/build/h5Engine/libh5Engine.so" && find "./third_party/centos7/muparserx-install/lib" -maxdepth 1 -name "libmuparserx.so*" | grep -q .'
```

Expected:

- The default build uses `docker/cuda-builder/centos7.Dockerfile`
- The single-platform build uses the matching platform Dockerfile, for example `docker/cuda-builder/rocky8.Dockerfile`
- The batch build covers `centos7`, `rocky8`, and `ubuntu2204`
- The default resulting image matches `BUILDER_IMAGE`
- If proxy settings are present, all builder platforms consume the same proxy input and `centos7` still completes its `yum` steps
- `/usr/include/uuid/uuid.h` and `ccache` exist in the base builder image
- `mpicc` is not present before the project-local dependency cache is prepared
- `scripts/prepare-builder-deps.sh --platform centos7` fills `./third_party/centos7`
- `./third_party/centos7/chrono-install/lib/libChronoEngine.so` exists
- `./third_party/centos7/eigen3-install/include/eigen3/Eigen/Core` exists
- `./third_party/centos7/openmpi-install/bin/mpicc` exists
- `./third_party/centos7/openmpi-install/lib/libmpi.so` exists
- `./third_party/centos7/hdf5-install/lib/libhdf5.so` exists
- `./third_party/centos7/h5engine-sph/build/h5Engine/libh5Engine.so` exists
- `./third_party/centos7/h5engine-dem/build/h5Engine/libh5Engine.so` exists
- `./third_party/centos7/muparserx-install/lib/libmuparserx.so*` exists

## 3. Validate local project build Compose

Run:

```bash
scripts/prepare-builder-deps.sh --platform centos7
scripts/compose.sh run --rm cuda-cxx-centos7
```

Expected:

- The sample CUDA/C++ project configures successfully
- The sample CUDA/C++ project builds successfully
- The prepared third_party tree under `${CUDA_CXX_THIRD_PARTY_ROOT}/centos7` is reused
- Build output is written under `${CUDA_CXX_BUILD_ROOT}/centos7`

## 4. Register shell runner entries

Run:

```bash
runner/register-shell-runner.sh gpu
runner/register-shell-runner.sh multi
```

Expected:

- GitLab shows one shared GPU runner
- GitLab shows one shared multi-GPU runner

## 5. Validate pipeline contract

Use [examples/gitlab-ci/shared-gpu-shell-runner.yml](../examples/gitlab-ci/shared-gpu-shell-runner.yml) in a test project.

Expected:

- `gpu-smoke` sees the GPU and toolchain
- `cuda-cmake-build` configures and builds the CUDA sample
- `multi-gpu-smoke` lands on the multi-GPU runner pool
