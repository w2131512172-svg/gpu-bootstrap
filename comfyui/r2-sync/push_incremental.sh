#!/usr/bin/env bash
set -euo pipefail

DRY_RUN=false

if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
fi

RCLONE_DRY_RUN_ARGS=()

if [ "$DRY_RUN" = true ]; then
    RCLONE_DRY_RUN_ARGS+=(--dry-run)
fi

# ============================================================
# AI Forge - R2 Push Incremental
# Purpose:
#   Push ONLY ComfyUI asset/state layers to Cloudflare R2.
#   Do NOT push rebuildable ComfyUI core source.
# ============================================================

COMFYUI_ROOT="${COMFYUI_ROOT:-/root/ComfyUI}"
R2_REMOTE="${R2_REMOTE:-r2-assets:comfyui-assets/ComfyUI}"
LOG_FILE="${LOG_FILE:-/root/rclone_push_incremental.log}"

RCLONE_CONF_SRC="${RCLONE_CONF_SRC:-/root/rclone.conf}"
RCLONE_CONF_DST="${RCLONE_CONF_DST:-/root/.config/rclone/rclone.conf}"

mkdir -p "$(dirname "$RCLONE_CONF_DST")"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

if [ "$DRY_RUN" = true ]; then
    log "[INFO] DRY RUN MODE ENABLED"
fi

die() {
  log "[ERROR] $*"
  exit 1
}

# ===== rclone config self-check =====
if [ ! -f "$RCLONE_CONF_DST" ]; then
  if [ -f "$RCLONE_CONF_SRC" ]; then
    cp "$RCLONE_CONF_SRC" "$RCLONE_CONF_DST"
    chmod 600 "$RCLONE_CONF_DST"
    log "[OK] rclone config copied: $RCLONE_CONF_SRC -> $RCLONE_CONF_DST"
  else
    die "rclone config not found: $RCLONE_CONF_DST or $RCLONE_CONF_SRC"
  fi
fi

[ -d "$COMFYUI_ROOT" ] || die "COMFYUI_ROOT not found: $COMFYUI_ROOT"

log "============================================================"
log "[INFO] AI Forge asset push started"
log "[INFO] COMFYUI_ROOT=$COMFYUI_ROOT"
log "[INFO] R2_REMOTE=$R2_REMOTE"
log "============================================================"

# ============================================================
# Asset/state whitelist
#
# Rule:
#   - Directories are synced individually.
#   - Files are copied individually.
#   - ComfyUI core source is intentionally NOT included.
# ============================================================

SYNC_DIRS=(
  "models"
  "custom_nodes"
  "deps"
  "user"
  "input"
  "output2"
  "lora1"
  "alembic_db"
)

SYNC_FILES=(
  "openapi.yaml"
  "comfy_stable_lock.txt"
  "comfy_env_lock.txt"
  "comfyui_stable_info.txt"
)

# Common exclusions inside asset directories.
# These prevent cache/runtime noise from entering R2.
COMMON_EXCLUDES=(
  "--exclude" "__pycache__/**"
  "--exclude" "*.pyc"
  "--exclude" ".git/**"
  "--exclude" ".DS_Store"
  "--exclude" "Thumbs.db"
  "--exclude" "*.tmp"
  "--exclude" "*.log"
)

# Directories where remote should mirror local exactly.
# custom_nodes is intentionally strict, because removed plugins should disappear remotely too.
STRICT_SYNC_DIRS=(
  "custom_nodes"
)

is_strict_dir() {
  local item="$1"
  for strict in "${STRICT_SYNC_DIRS[@]}"; do
    if [ "$item" = "$strict" ]; then
      return 0
    fi
  done
  return 1
}

sync_dir() {
  local item="$1"
  local src="$COMFYUI_ROOT/$item"
  local dst="$R2_REMOTE/$item"

  if [ ! -d "$src" ]; then
    log "[SKIP] dir not found: $src"
    return 0
  fi

  if is_strict_dir "$item"; then
    log "[SYNC][STRICT] $item -> $dst"
    rclone sync "$src" "$dst" \
      "${COMMON_EXCLUDES[@]}" \
      --transfers 8 \
      --checkers 16 \
      --fast-list \
      --progress \
      --log-file "$LOG_FILE" \
      --log-level INFO\
      "${RCLONE_DRY_RUN_ARGS[@]}"
  else
    log "[COPY][ADDITIVE] $item -> $dst"
    rclone copy "$src" "$dst" \
      "${COMMON_EXCLUDES[@]}" \
      --transfers 8 \
      --checkers 16 \
      --fast-list \
      --progress \
      --log-file "$LOG_FILE" \
      --log-level INFO\
      "${RCLONE_DRY_RUN_ARGS[@]}"
  fi
}

copy_file() {
  local item="$1"
  local src="$COMFYUI_ROOT/$item"
  local dst="$R2_REMOTE"

  if [ ! -f "$src" ]; then
    log "[SKIP] file not found: $src"
    return 0
  fi

  log "[COPY][FILE] $item -> $dst/"
  rclone copyto "$src" "$dst/$item" \
    --progress \
    --log-file "$LOG_FILE" \
    --log-level INFO\
    "${RCLONE_DRY_RUN_ARGS[@]}"
}

for item in "${SYNC_DIRS[@]}"; do
  sync_dir "$item"
done

for item in "${SYNC_FILES[@]}"; do
  copy_file "$item"
done

log "============================================================"
log "[OK] AI Forge asset push completed"
log "[INFO] Log: $LOG_FILE"
log "============================================================"
