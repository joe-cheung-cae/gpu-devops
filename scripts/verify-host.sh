#!/usr/bin/env bash
set -euo pipefail

# shellcheck disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/common/progress.sh"

progress_init 5
progress_step "Checking Docker"
docker --version

progress_step "Checking Compose"
if docker compose version >/dev/null 2>&1; then
  docker compose version
elif command -v docker-compose >/dev/null 2>&1; then
  docker-compose --version
else
  echo "Compose is missing. Install Docker Compose plugin or docker-compose." >&2
  exit 1
fi

progress_step "Checking NVIDIA driver"
nvidia-smi

progress_step "Checking NVIDIA Container Toolkit runtime"
docker info --format '{{json .Runtimes}}' | grep -q nvidia

progress_done "Host verification passed"
