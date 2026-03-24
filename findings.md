# Findings

## 2026-03-24

- Current builder implementation is hard-coded to `nvidia/cuda:11.7.1-devel-centos7`.
- Current build script only builds one image from `.env` via `BUILDER_IMAGE`.
- Current docs and examples assume a single published tag: `cuda11.7-cmake3.26-centos7`.
- Multi-platform support will require a platform matrix and a way to derive image tags per platform without breaking the runner image defaults.
- `nvidia/cuda:11.7.1-devel-centos8` is not published.
- `nvidia/cuda:11.7.1-devel-rockylinux8` and `nvidia/cuda:11.7.1-devel-ubuntu22.04` are published and suitable for the EL8 and Ubuntu variants.
- The new config model uses `BUILDER_IMAGE_FAMILY`, `BUILDER_DEFAULT_PLATFORM`, and `BUILDER_PLATFORMS` to derive per-platform tags while preserving a single default `BUILDER_IMAGE`.
