#!/usr/bin/env bash

if [[ -n "${PROGRESS_COMMON_LOADED:-}" ]]; then
  return 0
fi
PROGRESS_COMMON_LOADED=1

PROGRESS_TOTAL_STEPS=0
PROGRESS_CURRENT_STEP=0

progress_init() {
  PROGRESS_TOTAL_STEPS="${1:?missing total steps}"
  PROGRESS_CURRENT_STEP=0
}

progress_step() {
  local message="${1:?missing step message}"
  PROGRESS_CURRENT_STEP=$((PROGRESS_CURRENT_STEP + 1))
  printf '[%s/%s] %s\n' "${PROGRESS_CURRENT_STEP}" "${PROGRESS_TOTAL_STEPS}" "${message}"
}

progress_note() {
  local message="${1:?missing note message}"
  printf '%s\n' "${message}"
}

progress_done() {
  local message="${1:?missing completion message}"
  printf '[%s/%s] %s\n' "${PROGRESS_TOTAL_STEPS}" "${PROGRESS_TOTAL_STEPS}" "${message}"
}
