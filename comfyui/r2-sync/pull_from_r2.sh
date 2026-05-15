#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# AI Forge - R2 Pull Assets
# Purpose:
#   Pull ONLY ComfyUI asset/state layers from Cloudflare R2.
#   Requires ComfyUI core source to already exist locally.
# ============================================================

DRY_RUN=false

if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=true
fi

RCLONE_DRY_RUN_ARGS=()
if [ "$DRY_RUN" = true ]; then
  RCLONE_DRY_RUN_ARGS+=(--dry-run)
fi

COMFYUI_ROOT="${COMFYUI_ROOT:-/root/ComfyUI}"
R2_REMOTE="${R2_REMOTE:-r2-assets:comfyui-assets/ComfyUI}"
LOG_DIR="${AI_FORGE_LOG_DIR:-/root/ai_forge_logs}"
LOG_FILE="${LOG_FILE:-$LOG_DIR/r2_pull.log}"

RCLONE_CONF_SRC="${RCLONE_CONF_SRC:-/root/rclone.conf}"
RCLONE_CONF_DST="${RCLONE_CONF_DST:-/root/.config/rclone/rclone.conf}"

mkdir -p "$LOG_DIR"
mkdir -p "$(dirname "$RCLONE_CONF_DST")"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

die() {
  log "[ERROR] $*"
  exit 1
}

if [ "$DRY_RUN" = true ]; then
  log "[INFO] DRY RUN MODE ENABLED"
fi

# ===== rclone config self-check =====
if [ -d "$RCLONE_CONF_DST" ]; then
  die "rclone config path is a directory: $RCLONE_CONF_DST"
fi

if [ ! -f "$RCLONE_CONF_DST" ]; then
  if [ -f "$RCLONE_CONF_SRC" ]; then
    cp "$RCLONE_CONF_SRC" "$RCLONE_CONF_DST"
    chmod 600 "$RCLONE_CONF_DST"
    log "[OK] rclone config copied: $RCLONE_CONF_SRC -> $RCLONE_CONF_DST"
  else
    die "rclone config not found: $RCLONE_CONF_DST or $RCLONE_CONF_SRC"
  fi
fi

# ===== ComfyUI core must already exist =====
[ -d "$COMFYUI_ROOT" ] || die "COMFYUI_ROOT not found: $COMFYUI_ROOT"
[ -f "$COMFYUI_ROOT/main.py" ] || die "ComfyUI core not found: $COMFYUI_ROOT/main.py missing. Please git clone ComfyUI first."

log "============================================================"
log "[INFO] AI Forge asset pull started"
log "[INFO] COMFYUI_ROOT=$COMFYUI_ROOT"
log "[INFO] R2_REMOTE=$R2_REMOTE"
log "[INFO] LOG_FILE=$LOG_FILE"
log "============================================================"

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

COMMON_EXCLUDES=(
  "--exclude" "__pycache__/**"
  "--exclude" "*.pyc"
  "--exclude" ".git/**"
  "--exclude" ".DS_Store"
  "--exclude" "Thumbs.db"
  "--exclude" "*.tmp"
  "--exclude" "*.log"
)

pull_dir() {
  local item="$1"
  local src="$R2_REMOTE/$item"
  local dst="$COMFYUI_ROOT/$item"

  log "[COPY][DIR] $src -> $dst"

  mkdir -p "$dst"

  rclone copy "$src" "$dst" \
    "${COMMON_EXCLUDES[@]}" \
    --create-empty-src-dirs \
    --transfers 8 \
    --checkers 16 \
    --fast-list \
    --progress \
    --log-file "$LOG_FILE" \
    --log-level INFO \
    "${RCLONE_DRY_RUN_ARGS[@]}"
}

pull_file() {
  local item="$1"
  local src="$R2_REMOTE/$item"
  local dst="$COMFYUI_ROOT/$item"

  log "[COPY][FILE] $src -> $dst"

  rclone copyto "$src" "$dst" \
    --progress \
    --log-file "$LOG_FILE" \
    --log-level INFO \
    "${RCLONE_DRY_RUN_ARGS[@]}"
}

for item in "${SYNC_DIRS[@]}"; do
  pull_dir "$item"
done

for item in "${SYNC_FILES[@]}"; do
  pull_file "$item"
done

log "============================================================"
log "[OK] AI Forge asset pull completed"
log "[INFO] Log: $LOG_FILE"
log "============================================================"
