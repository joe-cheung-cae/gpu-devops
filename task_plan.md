# Multi-Platform Builder Support Plan

## Goal

Add support for multiple builder platforms so operators can build either one target platform or all supported targets, with matching docs and examples.

## Phases

- [completed] Confirm available CUDA base image tags and current repository constraints
- [completed] Define platform matrix and new image naming/configuration model
- [completed] Add failing tests for single-platform and batch-platform build flows
- [completed] Implement build script and Dockerfile restructuring
- [completed] Update docs, examples, and offline image handling defaults
- [completed] Run verification and summarize remaining constraints

## Errors Encountered

- `nvidia/cuda:11.7.1-devel-centos8` does not exist, so the EL8 variant was mapped to `rocky8` using `nvidia/cuda:11.7.1-devel-rockylinux8`.
