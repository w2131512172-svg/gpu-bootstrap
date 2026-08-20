#!/usr/bin/env bash
set -euo pipefail

R2_SYNC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_REPO_ROOT="$(cd "${R2_SYNC_DIR}/../.." && pwd)"
# shellcheck disable=SC1091
source "${CORE_REPO_ROOT}/core/storage/rclone.sh"

# ============================================================
# EverSpark Forge - R2 Pull Assets
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
LOG_DIR="${EVERSPARK_LOG_DIR:-/root/everspark_logs}"
LOG_FILE="${LOG_FILE:-$LOG_DIR/r2_pull.log}"

RCLONE_CONF_SRC="${RCLONE_CONF_SRC:-/root/rclone.conf}"
RCLONE_CONF_DST="${RCLONE_CONF_DST:-$(core_rclone_config_path)}"

mkdir -p "$LOG_DIR"

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

# ===== Core rclone connection =====
core_rclone_ensure_config "$RCLONE_CONF_SRC" "$RCLONE_CONF_DST"

# ===== ComfyUI core must already exist =====
[ -d "$COMFYUI_ROOT" ] || die "COMFYUI_ROOT not found: $COMFYUI_ROOT"
[ -f "$COMFYUI_ROOT/main.py" ] || die "ComfyUI core not found: $COMFYUI_ROOT/main.py missing. Please git clone ComfyUI first."

log "============================================================"
log "[INFO] EverSpark Forge asset pull started"
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

  core_rclone_copy "$src" "$dst" \
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

  core_rclone_copyto "$src" "$dst" \
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
log "[OK] EverSpark Forge asset pull completed"
log "[INFO] Log: $LOG_FILE"
log "============================================================"
