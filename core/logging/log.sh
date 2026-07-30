#!/usr/bin/env bash

# Shared logging helpers for EverSpark Forge Core.
# Source this file; do not execute it directly.

core_log_timestamp() {
  date '+%Y-%m-%d %H:%M:%S'
}

core_log() {
  local level="$1"
  shift

  local line
  line="[$(core_log_timestamp)] [${level}] $*"

  if [ -n "${CORE_LOG_FILE:-}" ]; then
    mkdir -p "$(dirname "$CORE_LOG_FILE")"
    printf '%s\n' "$line" | tee -a "$CORE_LOG_FILE"
  else
    printf '%s\n' "$line"
  fi
}

core_info() {
  core_log INFO "$@"
}

core_ok() {
  core_log OK "$@"
}

core_warn() {
  core_log WARN "$@"
}

core_error() {
  core_log ERROR "$@" >&2
}

core_die() {
  core_error "$@"
  return 1
}

core_section() {
  core_info "============================================================"
  core_info "$*"
  core_info "============================================================"
}
