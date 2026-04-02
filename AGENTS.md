# Repository Guidelines

## Project Structure & Module Organization
This repository packages a shared GitLab GPU runner platform for CUDA/CMake workloads. Keep changes scoped to the area they affect:

- `docker/cuda-builder/`: platform-specific builder Dockerfiles such as `centos7.Dockerfile` and `ubuntu2204.Dockerfile`
- `scripts/`: operational Bash entry points for host verification, image export/import, and Compose wrappers
- `runner/`: shell runner registration script and helper assets
- `tests/`: Bash test scripts for build, bundle, and runtime checks
- `examples/`: sample CUDA smoke project, `.env` examples, and GitLab CI snippets
- `docs/`: operator docs, self-checks, and implementation plans

## Build, Test, and Development Commands
- `bash tests/build-builder-image-test.sh`: verifies builder image selection and Dockerfile resolution
- `bash tests/offline-image-bundle-test.sh`: checks offline image export/import behavior with mocked Docker
- `bash tests/openmpi-runtime-test.sh`: validates the OpenMPI runtime contract in the builder image
- `bash tests/project-integration-bundle-test.sh`: verifies the portable project bundle workflow
- `bash -n scripts/*.sh runner/*.sh tests/*.sh`: syntax-check Bash changes before review
- `scripts/verify-host.sh`: confirm Docker, Compose, NVIDIA driver, and toolkit prerequisites
- `scripts/build-builder-image.sh --platform ubuntu2204`: build one builder image locally
- `runner/register-shell-runner.sh`: register the GitLab shell runner on a host

## Coding Style & Naming Conventions
Use Bash with `#!/usr/bin/env bash` and `set -euo pipefail`. Follow the existing script style: simple functions, quoted expansions, and uppercase environment variable names such as `BUILDER_IMAGE_FAMILY`. Use kebab-case for script names like `export-project-bundle.sh`, and keep Dockerfile names aligned to supported platforms: `<platform>.Dockerfile`. Preserve ShellCheck-friendly patterns such as explicit `SC1091` comments when sourcing `.env`.

## Testing Guidelines
Add or update a Bash test in `tests/` for behavior changes. Name test files after the target workflow, for example `offline-image-bundle-test.sh`. Mock external tools where possible, following the existing `PATH` override pattern. Run the focused test first, then a broader syntax pass with `bash -n`.

## Commit & Pull Request Guidelines
Recent commits use concise, imperative subjects such as `Improve environment file examples and comments` and `Add portable project integration bundle`. Keep commit titles short, specific, and capitalized; use a `docs:` prefix only when the change is documentation-only. PRs should describe the operator impact, list verification commands you ran, and include updated docs or examples when behavior or configuration changes.

## Security & Configuration Tips
Do not commit populated `.env` files, registration tokens, or generated archives under `artifacts/`. Pin published builder images to immutable tags instead of `latest`.
