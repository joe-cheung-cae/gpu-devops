#!/usr/bin/env bash
set -euo pipefail

echo "[1/5] Checking Docker"
docker --version

echo "[2/5] Checking Compose"
if docker compose version >/dev/null 2>&1; then
  docker compose version
elif command -v docker-compose >/dev/null 2>&1; then
  docker-compose --version
else
  echo "Compose is missing. Install Docker Compose plugin or docker-compose." >&2
  exit 1
fi

echo "[3/5] Checking NVIDIA driver"
nvidia-smi

echo "[4/5] Checking NVIDIA Container Toolkit runtime"
docker info --format '{{json .Runtimes}}' | grep -q nvidia

echo "[5/5] Host verification passed"
