#!/usr/bin/env bash
set -euo pipefail

TOOLKIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

exec /bin/bash "${TOOLKIT_ROOT}/third_party/install-third-party.sh" "$@"
