# Multi-Platform Builder Support Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add builder support for multiple OS platforms so operators can build either one selected platform or all supported platforms in a single command.

**Architecture:** Replace the single hard-coded builder Dockerfile with a platform matrix that maps a platform key to a dedicated Dockerfile and default image tag suffix. Update the build script to support `--platform <name>` and `--all-platforms`, keep a single default `BUILDER_IMAGE` for runner use, and introduce a list variable for offline export of multiple builder images.

**Tech Stack:** Bash, Docker, GitLab Runner, CUDA 11.7, Markdown docs

### Task 1: Add failing tests for build script platform selection

**Files:**
- Create: `tests/build-builder-image-test.sh`
- Modify: `scripts/build-builder-image.sh`

**Step 1: Write the failing test**

Cover:
- default build uses `.env` `BUILDER_IMAGE` and CentOS 7 Dockerfile
- `--platform ubuntu2204` selects the Ubuntu Dockerfile and derived image tag
- `--all-platforms` builds `centos7`, `rocky8`, and `ubuntu2204`

**Step 2: Run test to verify it fails**

Run: `bash tests/build-builder-image-test.sh`
Expected: FAIL because the current script only supports one Dockerfile and one image.

**Step 3: Write minimal implementation**

Add argument parsing, platform matrix lookup, and per-platform build loop.

**Step 4: Run test to verify it passes**

Run: `bash tests/build-builder-image-test.sh`
Expected: PASS

### Task 2: Split builder Dockerfiles by platform

**Files:**
- Create: `docker/cuda-builder/centos7.Dockerfile`
- Create: `docker/cuda-builder/rocky8.Dockerfile`
- Create: `docker/cuda-builder/ubuntu2204.Dockerfile`
- Delete: `docker/cuda-builder/Dockerfile`

**Step 1: Write the failing test**

Reuse the script-level test so it requires the new Dockerfile paths.

**Step 2: Run test to verify it fails**

Run: `bash tests/build-builder-image-test.sh`
Expected: FAIL until the platform Dockerfiles exist.

**Step 3: Write minimal implementation**

Create three Dockerfiles:
- `centos7`: preserve current behavior
- `rocky8`: use an EL8-compatible CUDA base and modern Python packages
- `ubuntu2204`: use the Ubuntu 22.04 CUDA base and apt packages

**Step 4: Run test to verify it passes**

Run: `bash tests/build-builder-image-test.sh`
Expected: PASS

### Task 3: Update offline image export and environment model

**Files:**
- Modify: `.env.example`
- Modify: `scripts/image-bundle-common.sh`
- Modify: `scripts/export-images.sh`
- Modify: `tests/offline-image-bundle-test.sh`

**Step 1: Write the failing test**

Require support for exporting multiple builder images from a new configuration variable, while preserving the default runner image behavior.

**Step 2: Run test to verify it fails**

Run: `bash tests/offline-image-bundle-test.sh`
Expected: FAIL because only a single builder image is exported today.

**Step 3: Write minimal implementation**

Add a variable such as `BUILDER_IMAGE_EXPORTS` or equivalent and include it in the export bundle image collection.

**Step 4: Run test to verify it passes**

Run: `bash tests/offline-image-bundle-test.sh`
Expected: PASS

### Task 4: Update examples and docs for the platform matrix

**Files:**
- Modify: `README.md`
- Modify: `docs/platform-contract.md`
- Modify: `docs/operations.md`
- Modify: `docs/self-check.md`
- Modify: `docs/tutorial.en.md`
- Modify: `docs/tutorial.zh-CN.md`
- Modify: `examples/gitlab-ci/shared-gpu-runner.yml`

**Step 1: Write the failing test**

No automated doc test exists; use targeted grep verification for new platform names and command examples.

**Step 2: Run verification to prove current docs are stale**

Run: `rg -n "cuda11.7-cmake3.26-centos7|--all-platforms|ubuntu2204|rocky8" README.md docs examples .env.example`
Expected: missing references for the new matrix before doc updates.

**Step 3: Write minimal implementation**

Document:
- supported platforms: `centos7`, `rocky8`, `ubuntu2204`
- command forms for building one platform or all platforms
- runner default image remaining a single selected tag
- offline export of multiple builder tags

**Step 4: Run verification**

Run: `rg -n "centos7|rocky8|ubuntu2204|--all-platforms" README.md docs examples .env.example`
Expected: all relevant docs include updated references.

### Task 5: Final verification

**Files:**
- Modify: `task_plan.md`
- Modify: `findings.md`
- Modify: `progress.md`

**Step 1: Run full verification**

Run:

```bash
bash tests/build-builder-image-test.sh
bash tests/offline-image-bundle-test.sh
bash -n scripts/build-builder-image.sh scripts/export-images.sh scripts/import-images.sh scripts/image-bundle-common.sh runner/register-runner.sh tests/build-builder-image-test.sh tests/offline-image-bundle-test.sh
```

Expected: all commands pass.

**Step 2: Record findings and completion status**

Update planning files with completed phases, verification evidence, and any remaining platform caveats.
