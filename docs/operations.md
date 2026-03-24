# Operations Guide

## Host preparation

1. Install Docker Engine.
2. Install Docker Compose plugin or standalone `docker-compose`.
3. Install the NVIDIA driver.
4. Install NVIDIA Container Toolkit and configure Docker to expose the `nvidia` runtime.
5. Reboot or restart Docker if runtime changes are not visible.

## Bootstrap

```bash
cp .env.example .env
scripts/verify-host.sh
scripts/build-builder-image.sh
scripts/build-builder-image.sh --platform ubuntu2204
scripts/build-builder-image.sh --all-platforms
scripts/export-images.sh
scripts/compose.sh up -d
```

If the destination host is air-gapped, copy the archive referenced by `IMAGE_ARCHIVE_PATH` to that host and run:

```bash
scripts/import-images.sh
```

## Runner registration

Register the standard GPU pool:

```bash
runner/register-runner.sh gpu
```

Register the multi-GPU pool:

```bash
runner/register-runner.sh multi
```

Both registrations append to `runner/config/config.toml`.

## Upgrade path

1. Build and publish a new builder image tag.
2. Update `BUILDER_IMAGE_FAMILY`, `BUILDER_DEFAULT_PLATFORM`, `BUILDER_PLATFORMS`, `RUNNER_DOCKER_IMAGE`, and `BUILDER_IMAGE` in `.env` if the platform matrix changes.
3. Re-export the offline image bundle if air-gapped hosts depend on it.
4. Restart the Runner service.
5. Validate the smoke pipeline in a test project.

## Rollback

1. Restore the previous image tag in `.env`.
2. Restart the Runner service.
3. Re-run the smoke pipeline.

## Cache management

Runner cache is stored under `runner/cache/`. Remove stale cache content during maintenance windows if jobs accumulate too much local state.
