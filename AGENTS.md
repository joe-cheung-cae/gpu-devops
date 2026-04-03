# Repository Guidelines

## Project Structure & Module Organization
This repository packages CUDA/CMake builder images plus image export/import tooling. Keep changes scoped to the area they affect:

- `docker/cuda-builder/`: platform-specific builder Dockerfiles
- `scripts/`: builder image build/export/import entry points
- `scripts/common/`: shared helpers for progress, environment loading, and archive handling
- `tests/`: build and image bundle tests
- `docs/`: builder image contract and rootless Docker deployment guide

## Build, Test, and Development Commands
- `bash tests/build-builder-image-test.sh`: verifies builder image selection and Dockerfile resolution
- `bash tests/offline-image-bundle-test.sh`: checks offline image export/import behavior with mocked Docker
- `bash tests/install-offline-tools-test.sh`: checks prefix installation and installed wrapper commands
- `bash -n scripts/*.sh scripts/common/*.sh tests/*.sh`: syntax-check Bash changes before review
- `scripts/build-builder-image.sh --platform ubuntu2204`: build one builder image locally
- `scripts/export/images.sh --platform centos7`: export a single builder image platform
- `scripts/install-offline-tools.sh --prefix /opt/gpu-devops`: install a self-contained offline tool tree
- `scripts/import/images.sh --input artifacts/offline-images.tar.gz`: load a previously exported builder image archive

## Coding Style & Naming Conventions
Use Bash with `#!/usr/bin/env bash` and `set -euo pipefail`. Keep scripts simple, quote expansions, use uppercase environment variables such as `BUILDER_IMAGE_FAMILY`, and keep Dockerfile names aligned to supported platforms: `<platform>.Dockerfile`. Preserve ShellCheck-friendly patterns such as explicit `SC1091` comments when sourcing `.env`.

## Testing Guidelines
Add or update a Bash test in `tests/` for behavior changes. Mock external tools where possible with the existing `PATH` override pattern. Run the focused test first, then a broader syntax pass with `bash -n`.

## Commit & Pull Request Guidelines
Recent commits use concise, imperative subjects such as `Trim repository to builder images` and `Update builder image docs`. Keep commit titles short, specific, and capitalized; use a `docs:` prefix only when the change is documentation-only. PRs should describe the operator impact, list verification commands you ran, and include updated docs or examples when behavior or configuration changes.

## Security & Configuration Tips
Do not commit populated `.env` files or generated archives under `artifacts/`. Pin published builder images to immutable tags instead of `latest`.
