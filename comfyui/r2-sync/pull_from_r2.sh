#!/usr/bin/env bash
set -euo pipefail

R2_SYNC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_REPO_ROOT="$(cd "${R2_SYNC_DIR}/../.." && pwd)"
# shellcheck disable=SC1091
source "${CORE_REPO_ROOT}/core/storage/rclone.sh"

LOG_DIR="${EVERSPARK_LOG_DIR:-/root/everspark_logs}"
LOG_FILE="${LOG_FILE:-${LOG_DIR}/r2.log}"
RCLONE_LOG="${RCLONE_LOG:-${LOG_DIR}/rclone.log}"
core_log_init r2.pull "$LOG_FILE"

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

RCLONE_CONF_SRC="${RCLONE_CONF_SRC:-/root/rclone.conf}"
RCLONE_CONF_DST="${RCLONE_CONF_DST:-$(core_rclone_config_path)}"



if [ "$DRY_RUN" = true ]; then
  core_info r2.status "DRY RUN MODE ENABLED"
fi

# ===== Core rclone connection =====
core_rclone_ensure_config "$RCLONE_CONF_SRC" "$RCLONE_CONF_DST"

# ===== ComfyUI core must already exist =====
[ -d "$COMFYUI_ROOT" ] || core_die r2.failed "COMFYUI_ROOT not found: $COMFYUI_ROOT"
[ -f "$COMFYUI_ROOT/main.py" ] || core_die r2.failed "ComfyUI core not found: $COMFYUI_ROOT/main.py missing. Please git clone ComfyUI first."
core_info r2.status "EverSpark Forge asset pull started"
core_info r2.status "COMFYUI_ROOT=$COMFYUI_ROOT"
core_info r2.status "R2_REMOTE=$R2_REMOTE"
core_info r2.status "LOG_FILE=$LOG_FILE"

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

  core_info r2.progress "[COPY][DIR] $src -> $dst"

  mkdir -p "$dst"

  core_rclone_copy "$src" "$dst" \
    "${COMMON_EXCLUDES[@]}" \
    --create-empty-src-dirs \
    --transfers 8 \
    --checkers 16 \
    --fast-list \
    --progress \
    --log-file "$RCLONE_LOG" \
    --log-level INFO \
    "${RCLONE_DRY_RUN_ARGS[@]}"
}

pull_file() {
  local item="$1"
  local src="$R2_REMOTE/$item"
  local dst="$COMFYUI_ROOT/$item"

  core_info r2.progress "[COPY][FILE] $src -> $dst"

  core_rclone_copyto "$src" "$dst" \
    --progress \
    --log-file "$RCLONE_LOG" \
    --log-level INFO \
    "${RCLONE_DRY_RUN_ARGS[@]}"
}

for item in "${SYNC_DIRS[@]}"; do
  pull_dir "$item"
done

for item in "${SYNC_FILES[@]}"; do
  pull_file "$item"
done
core_ok r2.status "EverSpark Forge asset pull completed"
core_info r2.status "Log: $LOG_FILE"

