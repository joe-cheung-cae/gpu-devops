# Platform Contract

## CUDA baseline

- Major version: CUDA 11
- Initial image baseline: `11.7.1-devel-ubuntu22.04`
- Host systems may run a newer driver as long as it remains compatible with CUDA 11.7 job containers

## Toolchain baseline

The standard builder image includes:

- `nvcc`
- `cmake`
- `ninja`
- `gcc/g++`
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
