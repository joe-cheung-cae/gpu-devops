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
```

Expected:

- Docker builds `docker/cuda-builder/Dockerfile`
- The resulting image matches `BUILDER_IMAGE`

## 3. Start Runner service

Run:

```bash
scripts/compose.sh up -d
scripts/compose.sh ps
```

Expected:

- `gitlab-runner` container is up
- Health status becomes healthy

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
