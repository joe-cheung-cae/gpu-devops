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

## 2. Build the standard builder image

Run:

```bash
cp .env.example .env
scripts/build-builder-image.sh
scripts/build-builder-image.sh --platform rocky8
scripts/build-builder-image.sh --all-platforms
docker run --rm "${BUILDER_IMAGE}" sh -lc 'mpicc --showme:version && mpicxx --showme:command && test -f /opt/openmpi/lib/libmpi.a && test ! -e /opt/openmpi/lib/libmpi.so && test -f /usr/local/include/eigen3/Eigen/Core && test -f "${HOME}/deps/chrono-install/lib/libChronoEngine.so" && ldd "${HOME}/deps/chrono-install/lib/libChronoEngine.so"'
docker run --rm "${BUILDER_IMAGE}" sh -lc 'test -f "${HOME}/deps/hdf5-install/lib/libhdf5.so" && ldd "${HOME}/deps/hdf5-install/lib/libhdf5.so" && "${HOME}/deps/hdf5-install/bin/h5cc" -showconfig >/dev/null'
```

Expected:

- The default build uses `docker/cuda-builder/centos7.Dockerfile`
- The single-platform build uses the matching platform Dockerfile, for example `docker/cuda-builder/rocky8.Dockerfile`
- The batch build covers `centos7`, `rocky8`, and `ubuntu2204`
- The default resulting image matches `BUILDER_IMAGE`
- If proxy settings are present, all builder platforms consume the same proxy input and `centos7` still completes its `yum` steps
- Eigen3 `3.4.0` is installed under `/usr/local/include/eigen3`
- OpenMPI 4.1.6 is available through `mpicc` / `mpicxx`
- `/opt/openmpi/lib/libmpi.a` exists and `/opt/openmpi/lib/libmpi.so` does not
- Chrono source exists under `${HOME}/deps/chrono`
- `${HOME}/deps/chrono-install/lib/libChronoEngine.so` exists and `ldd` prints successfully
- HDF5 is installed under `${HOME}/deps/hdf5-install`
- `${HOME}/deps/hdf5-install/lib/libhdf5.so` exists, `ldd` prints successfully, and `${HOME}/deps/hdf5-install/bin/h5cc -showconfig` works

## 3. Start Runner service

Run:

```bash
scripts/runner-compose.sh up -d
scripts/runner-compose.sh ps
```

Expected:

- `gitlab-runner` container is up
- Health status becomes healthy

## 3.1 Validate local project build Compose

Run:

```bash
scripts/compose.sh run --rm cuda-cxx-centos7
```

Expected:

- The sample CUDA/C++ project configures successfully
- The sample CUDA/C++ project builds successfully
- Build output is written under `${CUDA_CXX_BUILD_ROOT}/centos7`

## 4. Register Runner entries

Run:

```bash
runner/register-runner.sh gpu
runner/register-runner.sh multi
```

Expected:

- GitLab shows one shared GPU runner
- GitLab shows one shared multi-GPU runner

## 5. Validate pipeline contract

Use [examples/gitlab-ci/shared-gpu-runner.yml](/home/joe/repo/gpu-devops/examples/gitlab-ci/shared-gpu-runner.yml) in a test project.

Expected:

- `gpu-smoke` sees the GPU and toolchain
- `cuda-cmake-build` configures and builds the CUDA sample
- `multi-gpu-smoke` lands on the multi-GPU runner pool
