# Platform Contract

## CUDA baseline

- Major version: CUDA 11
- Builder image family: `cuda11.7-cmake3.26`
- Supported platform keys:
  - `centos7` -> `nvidia/cuda:11.7.1-devel-centos7`
  - `rocky8` -> `nvidia/cuda:11.7.1-devel-rockylinux8`
  - `ubuntu2204` -> `nvidia/cuda:11.7.1-devel-ubuntu22.04`
- Host systems may run a newer driver as long as it remains compatible with CUDA 11.7 job containers

## Platform notes

- `centos7` is still supported for compatibility, but it is end-of-life.
- The CentOS 7 Dockerfile rewrites base repositories and SCL repositories to `vault.centos.org`.
- The CentOS 7 image uses `rh-python38` and keeps `urllib3<2` for compatibility with the older OpenSSL stack.
- All builder platforms install Eigen3 `3.4.0` from source to `/usr/local`, so downstream CMake discovery stays consistent.
- All builder platforms clone Project Chrono to `${HOME}/deps/chrono`, pin it to commit `3eb56218b`, and install it to `${HOME}/deps/chrono-install`.
- All builder platforms build HDF5 `1.14.1-2` from the bundled `docker/cuda-builder/deps/CMake-hdf5-1.14.1-2.tar.gz` archive and install it to `${HOME}/deps/hdf5-install`.
- All builder platforms unpack `h5engine-sph` and `h5engine-dem` under `${HOME}/deps`, replace the bundled Linux HDF5 headers and shared libraries with `${HOME}/deps/hdf5-install`, and rebuild them in `Release`.
- Chrono is configured with `-DUSE_BULLET_DOUBLE=ON -DUSE_SIMD=OFF`.
- HDF5 is configured with zlib support enabled, so the platform requires the matching zlib development package during image build.
- `rocky8` uses the Rocky Linux 8 CUDA image and installs Python 3 from the system package set.
- `rocky8` uses `gcc-toolset-11` for the Chrono build so static `libstdc++` and `libgcc` linking works consistently.
- `ubuntu2204` uses the Ubuntu 22.04 CUDA image and installs toolchain packages with `apt`.
- If your organization has an internal RPM/YUM mirror, prefer switching public repository references to internal mirrors.

## Toolchain baseline

The standard builder image includes:

- `nvcc`
- `cmake`
- `ninja`
- `gcc/g++`
- `Eigen3 3.4.0`
- `OpenMPI 4.1.6` with static libraries and C/C++ wrappers
- `Project Chrono` at commit `3eb56218b`
- `HDF5 1.14.1-2` with zlib compression support
- `h5engine-sph` rebuilt against the installed HDF5 runtime
- `h5engine-dem` rebuilt against the installed HDF5 runtime
- `git`
- `gdb`
- `python3` and `pip`
- `conan`

## Shared usage contract

- Projects reference the platform image directly in `.gitlab-ci.yml`
- Projects use tags to select the correct runner pool
- The platform maintains the base compiler and CUDA toolchain only
- Projects install any domain-specific libraries in their own pipeline steps or their own derived image

## Runner pools

### Default GPU pool

- Tags: `gpu`, `cuda`, `cuda-11`
- Intended for single-GPU jobs
- Higher concurrency than the multi-GPU pool
- Default registration limit comes from `RUNNER_GPU_CONCURRENCY`

### Multi-GPU pool

- Tags: `gpu-multi`, `cuda`, `cuda-11`
- Intended for jobs that need more than one GPU visible in the container
- Lower concurrency to reduce contention
- Default registration limit comes from `RUNNER_MULTI_GPU_CONCURRENCY`

## Limitations

- v1 does not enforce per-job GPU count at the GitLab scheduler level
- Multi-GPU jobs are isolated by runner pool rather than exact GPU reservation
- v1 does not expose project-specific package sets
