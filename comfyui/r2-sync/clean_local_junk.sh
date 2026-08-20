#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY_RUN=false

if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=true
fi

COMFYUI_ROOT="${COMFYUI_ROOT:-/root/ComfyUI}"
LOG_DIR="${EVERSPARK_LOG_DIR:-/root/everspark_logs}"
LOG_FILE="${LOG_FILE:-$LOG_DIR/r2_push.log}"
JUNK_RULES_FILE="${JUNK_RULES_FILE:-$SCRIPT_DIR/junk_rules.sh}"

mkdir -p "$LOG_DIR"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

die() {
  log "[ERROR] $*"
  exit 1
}

[ -d "$COMFYUI_ROOT" ] || die "COMFYUI_ROOT not found: $COMFYUI_ROOT"
[ -f "$JUNK_RULES_FILE" ] || die "junk rules file not found: $JUNK_RULES_FILE"

# shellcheck disable=SC1090
source "$JUNK_RULES_FILE"

remove_path() {
  local path="$1"

  if [ ! -e "$path" ]; then
    return 0
  fi

  if [ "$DRY_RUN" = true ]; then
    log "[DRY-RUN] Would remove path: $path"
    return 0
  fi

  rm -rf -- "$path"
  log "[CLEAN] Removed path: $path"
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
            log "[DRY-RUN] Would remove dir: $path"
          done
    else
      find "$COMFYUI_ROOT" -type d -name "$dir_name" -prune -print 2>/dev/null \
        | while IFS= read -r path; do
            rm -rf -- "$path"
            log "[CLEAN] Removed dir: $path"
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
            log "[DRY-RUN] Would remove file: $path"
          done
    else
      find "$COMFYUI_ROOT" -type f -name "$glob" -print -delete 2>/dev/null \
        | while IFS= read -r path; do
            log "[CLEAN] Removed file: $path"
          done
    fi
  done
}

log "============================================================"
log "[INFO] EverSpark Forge local junk cleanup started"
log "[INFO] COMFYUI_ROOT=$COMFYUI_ROOT"
log "[INFO] JUNK_RULES_FILE=$JUNK_RULES_FILE"
if [ "$DRY_RUN" = true ]; then
  log "[INFO] DRY RUN MODE ENABLED"
fi
log "============================================================"

clean_known_paths
clean_dirs_by_name
clean_files_by_glob

log "[OK] EverSpark Forge local junk cleanup completed"
