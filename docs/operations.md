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
scripts/compose.sh up -d
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
2. Update `RUNNER_DOCKER_IMAGE` and `BUILDER_IMAGE` in `.env`.
3. Restart the Runner service.
4. Validate the smoke pipeline in a test project.

## Rollback

1. Restore the previous image tag in `.env`.
2. Restart the Runner service.
3. Re-run the smoke pipeline.

## Cache management

Runner cache is stored under `runner/cache/`. Remove stale cache content during maintenance windows if jobs accumulate too much local state.
