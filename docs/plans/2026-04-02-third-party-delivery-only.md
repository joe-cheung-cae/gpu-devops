# Third Party Delivery Only Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make this repository a pure `third_party` delivery source for target project repositories, with no submodule lifecycle management for the target repo.

**Architecture:** Keep the current repository responsible for preparing, packaging, exporting, and importing `third_party` assets only. The target project repository owns its own `third_party` submodule or snapshot. `docker compose` and the shell scripts should consume the delivered `third_party` tree from the target project workspace, but this repository must not run any `git submodule` write/update operations for that target workspace.

**Tech Stack:** Bash, Docker Compose, GitLab CI shell runners, portable project bundle scripts, Bash-based regression tests.

### Task 1: Rebase dependency paths and bundle payloads onto `third_party`

**Files:**
- Modify: `docker-compose.yml`
- Modify: `scripts/prepare-builder-deps.sh`
- Modify: `scripts/install-third-party.sh`
- Modify: `scripts/common/project-bundle.sh`
- Modify: `scripts/common/third-party-registry.sh`

**Step 1: Write the failing test**

Add or update tests so the expected install root and bundle import root are `third_party/<platform>`.

**Step 2: Run test to verify it fails**

Run: `bash tests/prepare-builder-deps-test.sh`
Expected: FAIL because it still asserts the legacy dependency-root naming.

**Step 3: Write minimal implementation**

Update the root variables and compose environment so `third_party` is the canonical project dependency root and bundle import writes `.gpu-devops/third_party`.

**Step 4: Run test to verify it passes**

Run: `bash tests/prepare-builder-deps-test.sh`
Expected: PASS.

**Step 5: Commit**

```bash
git add docker-compose.yml scripts/prepare-builder-deps.sh scripts/install-third-party.sh scripts/common/project-bundle.sh scripts/common/third-party-registry.sh tests/prepare-builder-deps-test.sh
git commit -m "Refactor project dependency root to third_party"
```

### Task 2: Deliver `third_party` in project bundles without submodule lifecycle logic

**Files:**
- Modify: `scripts/export/project-bundle.sh`
- Modify: `scripts/import/project-bundle.sh`
- Modify: `scripts/export/images.sh`
- Modify: `scripts/import/images.sh`
- Modify: `scripts/export/project-bundle.sh`
- Modify: `tests/project-integration-bundle-test.sh`

**Step 1: Write the failing test**

Add regression coverage that exported bundles contain the `third_party` delivery payload and imported bundles do not attempt `git submodule update/add/sync`.

**Step 2: Run test to verify it fails**

Run: `bash tests/project-integration-bundle-test.sh`
Expected: FAIL on the old dependency-root and submodule assumptions.

**Step 3: Write minimal implementation**

Ensure export/import moves `third_party` as project content only, and remove any target-repo submodule lifecycle hooks.

**Step 4: Run test to verify it passes**

Run: `bash tests/project-integration-bundle-test.sh`
Expected: PASS.

**Step 5: Commit**

```bash
git add scripts/export/project-bundle.sh scripts/import/project-bundle.sh scripts/export/images.sh scripts/import/images.sh tests/project-integration-bundle-test.sh
git commit -m "Deliver third_party in project bundles"
```

### Task 3: Rewrite docs and examples to describe delivery-only ownership

**Files:**
- Modify: `README.md`
- Modify: `docs/operations.md`
- Modify: `docs/usage.en.md`
- Modify: `docs/usage.zh-CN.md`
- Modify: `docs/tutorial.en.md`
- Modify: `docs/tutorial.zh-CN.md`
- Modify: `docs/offline-env-configuration.md`
- Modify: `docs/self-check.md`
- Modify: `docs/platform-contract.md`
- Modify: `docs/gitlab-ci-multi-environment.md`
- Modify: `examples/gitlab-ci/shared-gpu-shell-runner.yml`
- Modify: `examples/env/cuda-cxx.env.example`
- Modify: `tests/offline-env-doc-test.sh`
- Modify: `tests/offline-runner-workflow-doc-test.sh`
- Modify: `tests/shell-runner-doc-test.sh`

**Step 1: Write the failing test**

Add or update assertions that docs mention `third_party` delivery ownership and stop describing this repo as the submodule manager.

**Step 2: Run test to verify it fails**

Run: `bash tests/offline-env-doc-test.sh`
Expected: FAIL until the wording and paths are updated.

**Step 3: Write minimal implementation**

Rewrite the docs and examples to say the current repository delivers `third_party`, while the target project repository owns its `third_party` submodule or snapshot.

**Step 4: Run test to verify it passes**

Run: `bash tests/offline-env-doc-test.sh`
Expected: PASS.

**Step 5: Commit**

```bash
git add README.md docs/operations.md docs/usage.en.md docs/usage.zh-CN.md docs/tutorial.en.md docs/tutorial.zh-CN.md docs/offline-env-configuration.md docs/self-check.md docs/platform-contract.md docs/gitlab-ci-multi-environment.md examples/gitlab-ci/shared-gpu-shell-runner.yml examples/env/cuda-cxx.env.example tests/offline-env-doc-test.sh tests/offline-runner-workflow-doc-test.sh tests/shell-runner-doc-test.sh
git commit -m "Rewrite docs for third_party delivery ownership"
```

### Task 4: Remove target-project submodule write assumptions from tests and guardrails

**Files:**
- Modify: `tests/script-layout-test.sh`
- Modify: `tests/build-builder-image-test.sh`
- Modify: `tests/compose-command-test.sh`
- Modify: `tests/prepare-builder-deps-test.sh`
- Modify: `tests/third-party-registry-test.sh`
- Modify: `tests/project-integration-bundle-test.sh`

**Step 1: Write the failing test**

Add a static guard that fails if repo code still includes `git submodule add`, `git submodule update`, `git submodule sync`, or `submodule foreach`.

**Step 2: Run test to verify it fails**

Run: `bash tests/script-layout-test.sh`
Expected: FAIL until the new guard is in place and the old assumptions are removed.

**Step 3: Write minimal implementation**

Update the tests to cover the new canonical `third_party` flow and stop asserting target-repo submodule lifecycle behavior.

**Step 4: Run test to verify it passes**

Run: `bash tests/script-layout-test.sh`
Expected: PASS.

**Step 5: Commit**

```bash
git add tests/script-layout-test.sh tests/build-builder-image-test.sh tests/compose-command-test.sh tests/prepare-builder-deps-test.sh tests/third-party-registry-test.sh tests/project-integration-bundle-test.sh
git commit -m "Refresh tests for third_party delivery only"
```
