#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck disable=SC1091
source "${CORE_REPO_ROOT}/core/logging/log.sh"

LOG_DIR="${EVERSPARK_LOG_DIR:-/root/everspark_logs}"
LOG_FILE="${LOG_FILE:-${LOG_DIR}/r2.log}"
core_log_init r2.push.clean "$LOG_FILE"

DRY_RUN=false
R2_ARGS=()
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=true
  R2_ARGS+=(--dry-run)
fi

CLEAN_SCRIPT="$SCRIPT_DIR/clean_local_junk.sh"
PUSH_SCRIPT="$SCRIPT_DIR/push_incremental.sh"

if [ ! -f "$CLEAN_SCRIPT" ]; then
  core_die r2.script.missing "Local cleanup script was not found" "path=$CLEAN_SCRIPT"
  exit 1
fi
if [ ! -f "$PUSH_SCRIPT" ]; then
  core_die r2.script.missing "Incremental push script was not found" "path=$PUSH_SCRIPT"
  exit 1
fi

core_info r2.push.clean.start "Starting clean incremental R2 push" "dry_run=$DRY_RUN"
core_run_step r2.cleanup bash "$CLEAN_SCRIPT" "${R2_ARGS[@]}"
core_run_step r2.push bash "$PUSH_SCRIPT" "${R2_ARGS[@]}"
core_ok r2.push.clean.complete "Clean incremental R2 push completed" "dry_run=$DRY_RUN"
