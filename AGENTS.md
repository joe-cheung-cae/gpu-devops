# Repository Guidelines

## Project Structure & Module Organization
This repository packages CUDA/CMake builder images plus image export/import tooling. Keep changes scoped to the area they affect:

- `docker/cuda-builder/`: platform-specific builder Dockerfiles such as `centos7.Dockerfile` and `ubuntu2204.Dockerfile`
- `scripts/`: Bash entry points for builder image builds and image export/import
- `scripts/common/`: shared helpers for progress output, environment loading, and image archive handling
- `tests/`: Bash test scripts for build and image bundle checks
- `docs/`: builder image contract and rootless Docker deployment guide

## Build, Test, and Development Commands
- `bash tests/build-builder-image-test.sh`: verifies builder image selection and Dockerfile resolution
- `bash tests/offline-image-bundle-test.sh`: checks offline image export/import behavior with mocked Docker
- `bash -n scripts/*.sh scripts/common/*.sh tests/*.sh`: syntax-check Bash changes before review
- `scripts/build-builder-image.sh --platform ubuntu2204`: build one builder image locally
- `scripts/export/images.sh --only-build-images`: export the builder image matrix
- `scripts/import/images.sh --input artifacts/offline-images.tar.gz`: load a previously exported builder image archive

## Coding Style & Naming Conventions
Use Bash with `#!/usr/bin/env bash` and `set -euo pipefail`. Follow the existing script style: simple functions, quoted expansions, and uppercase environment variable names such as `BUILDER_IMAGE_FAMILY`. Use kebab-case for script names, and keep Dockerfile names aligned to supported platforms: `<platform>.Dockerfile`. Preserve ShellCheck-friendly patterns such as explicit `SC1091` comments when sourcing `.env`.

## Testing Guidelines
Add or update a Bash test in `tests/` for behavior changes. Name test files after the target workflow, for example `offline-image-bundle-test.sh`. Mock external tools where possible, following the existing `PATH` override pattern. Run the focused test first, then a broader syntax pass with `bash -n`.

## Commit & Pull Request Guidelines
Recent commits use concise, imperative subjects such as `Improve environment file examples and comments` and `Trim repository to builder images`. Keep commit titles short, specific, and capitalized; use a `docs:` prefix only when the change is documentation-only. PRs should describe the operator impact, list verification commands you ran, and include updated docs or examples when behavior or configuration changes.

## Security & Configuration Tips
Do not commit populated `.env` files or generated archives under `artifacts/`. Pin published builder images to immutable tags instead of `latest`.
