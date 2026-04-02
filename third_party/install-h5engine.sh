#!/usr/bin/env bash
set -euo pipefail

TOOLKIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

exec /bin/bash "${TOOLKIT_ROOT}/docker/cuda-builder/install-h5engine.sh" "$@"
