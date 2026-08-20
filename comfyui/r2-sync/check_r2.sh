#!/usr/bin/env bash
set -u

R2_SYNC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_REPO_ROOT="$(cd "${R2_SYNC_DIR}/../.." && pwd)"
# shellcheck disable=SC1091
source "${CORE_REPO_ROOT}/core/storage/rclone.sh"

LOG_DIR="${EVERSPARK_LOG_DIR:-/root/everspark_logs}"
LOG_FILE="${LOG_FILE:-${LOG_DIR}/r2.log}"
RCLONE_LOG="${RCLONE_LOG:-${LOG_DIR}/rclone.log}"
core_log_init r2.check "$LOG_FILE"

COMFYUI_ROOT="${COMFYUI_ROOT:-/root/ComfyUI}"
R2_REMOTE="${R2_REMOTE:-r2-assets:comfyui-assets/ComfyUI}"
RCLONE_CONF_SRC="${RCLONE_CONF_SRC:-/root/rclone.conf}"
RCLONE_CONF_DST="${RCLONE_CONF_DST:-$(core_rclone_config_path)}"

CHECK_FAILED=0

record_failure() {
  core_error r2.check "$@"
  CHECK_FAILED=1
}

core_info r2.check.start "Checking the R2 data layer" \
  "comfyui_root=$COMFYUI_ROOT" "remote=$R2_REMOTE"

if core_rclone_require; then
  RCLONE_VERSION="$(rclone version 2>/dev/null | head -n 1)"
  core_ok r2.binary.ready "rclone is available" \
    "path=$(command -v rclone)" "version=$RCLONE_VERSION"
else
  record_failure "rclone command was not found"
fi

if ! core_rclone_ensure_config "$RCLONE_CONF_SRC" "$RCLONE_CONF_DST"; then
  record_failure "Unable to install the rclone runtime configuration"
fi

if [ -d "$RCLONE_CONF_SRC" ]; then
  record_failure "rclone source configuration is a directory: $RCLONE_CONF_SRC"
elif [ -f "$RCLONE_CONF_SRC" ]; then
  core_ok r2.config.source.ready "rclone source configuration exists" "path=$RCLONE_CONF_SRC"
else
  core_warn r2.config.source.missing "rclone source configuration was not found" \
    "path=$RCLONE_CONF_SRC"
fi

if [ -d "$RCLONE_CONF_DST" ]; then
  record_failure "rclone runtime configuration is a directory: $RCLONE_CONF_DST"
elif [ -f "$RCLONE_CONF_DST" ]; then
  core_ok r2.config.runtime.ready "rclone runtime configuration exists" "path=$RCLONE_CONF_DST"
else
  record_failure "rclone runtime configuration is missing: $RCLONE_CONF_DST"
fi

if core_rclone_lsd "$R2_REMOTE" >/dev/null 2>>"$RCLONE_LOG"; then
  core_ok r2.remote.ready "R2 remote is accessible" "remote=$R2_REMOTE"
else
  record_failure "Unable to access R2 remote: $R2_REMOTE"
fi

if [ -d "$COMFYUI_ROOT" ]; then
  core_ok r2.local.root.ready "ComfyUI root exists" "path=$COMFYUI_ROOT"
else
  record_failure "ComfyUI root is missing: $COMFYUI_ROOT"
fi

if [ -f "$COMFYUI_ROOT/main.py" ]; then
  core_ok r2.local.core.ready "ComfyUI core detected"
else
  core_warn r2.local.core.missing "ComfyUI core is missing" "path=$COMFYUI_ROOT/main.py"
fi

if [ "$CHECK_FAILED" -eq 0 ]; then
  core_ok r2.check.complete "R2 data layer self-check passed"
  exit 0
fi

record_failure "R2 data layer self-check failed"
exit 1
