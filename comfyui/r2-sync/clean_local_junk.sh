#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck disable=SC1091
source "${CORE_REPO_ROOT}/core/logging/log.sh"

LOG_DIR="${EVERSPARK_LOG_DIR:-/root/everspark_logs}"
LOG_FILE="${LOG_FILE:-${LOG_DIR}/r2.log}"
core_log_init r2.cleanup "$LOG_FILE"
DRY_RUN=false

if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=true
fi

COMFYUI_ROOT="${COMFYUI_ROOT:-/root/ComfyUI}"
JUNK_RULES_FILE="${JUNK_RULES_FILE:-$SCRIPT_DIR/junk_rules.sh}"



[ -d "$COMFYUI_ROOT" ] || core_die r2.failed "COMFYUI_ROOT not found: $COMFYUI_ROOT"
[ -f "$JUNK_RULES_FILE" ] || core_die r2.failed "junk rules file not found: $JUNK_RULES_FILE"

# shellcheck disable=SC1090
source "$JUNK_RULES_FILE"

remove_path() {
  local path="$1"

  if [ ! -e "$path" ]; then
    return 0
  fi

  if [ "$DRY_RUN" = true ]; then
    core_info r2.progress "[DRY-RUN] Would remove path: $path"
    return 0
  fi

  rm -rf -- "$path"
  core_info r2.progress "[CLEAN] Removed path: $path"
}

clean_known_paths() {
  local rel

  for rel in "${JUNK_LOCAL_REL_PATHS[@]}"; do
    remove_path "$COMFYUI_ROOT/$rel"
  done
}

clean_dirs_by_name() {
  local dir_name

  for dir_name in "${JUNK_LOCAL_DIR_NAMES[@]}"; do
    if [ "$DRY_RUN" = true ]; then
      find "$COMFYUI_ROOT" -type d -name "$dir_name" -print 2>/dev/null \
        | while IFS= read -r path; do
            core_info r2.progress "[DRY-RUN] Would remove dir: $path"
          done
    else
      find "$COMFYUI_ROOT" -type d -name "$dir_name" -prune -print 2>/dev/null \
        | while IFS= read -r path; do
            rm -rf -- "$path"
            core_info r2.progress "[CLEAN] Removed dir: $path"
          done
    fi
  done
}

clean_files_by_glob() {
  local glob

  for glob in "${JUNK_LOCAL_FILE_GLOBS[@]}"; do
    if [ "$DRY_RUN" = true ]; then
      find "$COMFYUI_ROOT" -type f -name "$glob" -print 2>/dev/null \
        | while IFS= read -r path; do
            core_info r2.progress "[DRY-RUN] Would remove file: $path"
          done
    else
      find "$COMFYUI_ROOT" -type f -name "$glob" -print -delete 2>/dev/null \
        | while IFS= read -r path; do
            core_info r2.progress "[CLEAN] Removed file: $path"
          done
    fi
  done
}
core_info r2.status "EverSpark Forge local junk cleanup started"
core_info r2.status "COMFYUI_ROOT=$COMFYUI_ROOT"
core_info r2.status "JUNK_RULES_FILE=$JUNK_RULES_FILE"
if [ "$DRY_RUN" = true ]; then
  core_info r2.status "DRY RUN MODE ENABLED"
fi

clean_known_paths
clean_dirs_by_name
clean_files_by_glob

core_ok r2.status "EverSpark Forge local junk cleanup completed"

