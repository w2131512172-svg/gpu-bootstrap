#!/usr/bin/env bash
set -euo pipefail

R2_SYNC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_REPO_ROOT="$(cd "${R2_SYNC_DIR}/../.." && pwd)"
# shellcheck disable=SC1091
source "${CORE_REPO_ROOT}/core/storage/rclone.sh"

DRY_RUN=false

if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
fi

RCLONE_DRY_RUN_ARGS=()

if [ "$DRY_RUN" = true ]; then
    RCLONE_DRY_RUN_ARGS+=(--dry-run)
fi

# ============================================================
# EverSpark Forge - R2 Push Incremental
# Purpose:
#   Push ONLY ComfyUI asset/state layers to Cloudflare R2.
#   Do NOT push rebuildable ComfyUI core source.
#
# Model rule:
#   - Normal ComfyUI restore layer remains:
#       r2-assets:comfyui-assets/ComfyUI
#   - Cold models live outside the default restore layer:
#       r2-assets:comfyui-assets/models_cold
#   - Local loras/checkpoints are classified by remote state:
#       default exists -> update default layer
#       cold exists    -> skip, because it was temporarily pulled from cold storage
#       neither exists -> upload to cold layer as a new model
# ============================================================

COMFYUI_ROOT="${COMFYUI_ROOT:-/root/ComfyUI}"
R2_REMOTE="${R2_REMOTE:-r2-assets:comfyui-assets/ComfyUI}"
R2_ROOT_REMOTE="${R2_ROOT_REMOTE:-r2-assets:comfyui-assets}"
R2_COLD_REMOTE="${R2_COLD_REMOTE:-$R2_ROOT_REMOTE/models_cold}"
LOG_DIR="${EVERSPARK_LOG_DIR:-/root/everspark_logs}"
LOG_FILE="${LOG_FILE:-$LOG_DIR/r2_push.log}"

RCLONE_CONF_SRC="${RCLONE_CONF_SRC:-/root/rclone.conf}"
RCLONE_CONF_DST="${RCLONE_CONF_DST:-$(core_rclone_config_path)}"

mkdir -p "$LOG_DIR"

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

# ===== Core rclone connection =====
core_rclone_ensure_config "$RCLONE_CONF_SRC" "$RCLONE_CONF_DST"

[ -d "$COMFYUI_ROOT" ] || die "COMFYUI_ROOT not found: $COMFYUI_ROOT"

log "============================================================"
log "[INFO] EverSpark Forge asset push started"
log "[INFO] COMFYUI_ROOT=$COMFYUI_ROOT"
log "[INFO] R2_REMOTE=$R2_REMOTE"
log "[INFO] R2_COLD_REMOTE=$R2_COLD_REMOTE"
log "[INFO] LOG_FILE=$LOG_FILE"
log "============================================================"

# ============================================================
# Stage 1: pre-push cleanup
#
# These files are runtime/cache state. They should not be persisted to R2,
# otherwise pull_from_r2.sh will bring them back and waste bandwidth/storage.
# ============================================================

pre_push_cleanup() {
  log "[INFO] Running pre-push cleanup"

  if [ "$DRY_RUN" = true ]; then
    log "[DRY-RUN] Would remove: $COMFYUI_ROOT/user/__manager/cache"
    log "[DRY-RUN] Would remove: $COMFYUI_ROOT/user/*.lock"
    log "[DRY-RUN] Would remove recursively: $COMFYUI_ROOT/user/**/*.lock"
    return 0
  fi

  rm -rf "$COMFYUI_ROOT/user/__manager/cache"
  rm -f "$COMFYUI_ROOT"/user/*.lock 2>/dev/null || true

  if [ -d "$COMFYUI_ROOT/user" ]; then
    find "$COMFYUI_ROOT/user" -name "*.lock" -type f -delete
  fi

  log "[OK] Pre-push cleanup completed"
}

pre_push_cleanup

# ============================================================
# Asset/state whitelist
#
# Rule:
#   - Directories are synced individually.
#   - Files are copied individually.
#   - ComfyUI core source is intentionally NOT included.
#   - models is handled separately because loras/checkpoints now support
#     cold-layer classification.
# ============================================================

SYNC_DIRS=(
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
  "--exclude" "user/__manager/cache/**"
  "--exclude" "*.lock"
)

MODEL_MISC_EXCLUDES=(
  "--exclude" "loras/**"
  "--exclude" "checkpoints/**"
)

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
    core_rclone_sync "$src" "$dst" \
      "${COMMON_EXCLUDES[@]}" \
      --transfers 8 \
      --checkers 16 \
      --fast-list \
      --progress \
      --log-file "$LOG_FILE" \
      --log-level INFO \
      "${RCLONE_DRY_RUN_ARGS[@]}"
  else
    log "[COPY][ADDITIVE] $item -> $dst"
    core_rclone_copy "$src" "$dst" \
      "${COMMON_EXCLUDES[@]}" \
      --transfers 8 \
      --checkers 16 \
      --fast-list \
      --progress \
      --log-file "$LOG_FILE" \
      --log-level INFO \
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
  core_rclone_copyto "$src" "$dst/$item" \
    --progress \
    --log-file "$LOG_FILE" \
    --log-level INFO \
    "${RCLONE_DRY_RUN_ARGS[@]}"
}

remote_file_exists_in_list() {
  local list_file="$1"
  local filename="$2"
  grep -Fxq -- "$filename" "$list_file"
}

list_remote_files() {
  local remote_dir="$1"
  local output_file="$2"

  : > "$output_file"
  core_rclone_lsf "$remote_dir" --files-only > "$output_file" 2>/dev/null || true
}

copy_model_file() {
  local src_file="$1"
  local dst_file="$2"

  core_rclone_copyto "$src_file" "$dst_file" \
    --progress \
    --log-file "$LOG_FILE" \
    --log-level INFO \
    "${RCLONE_DRY_RUN_ARGS[@]}"
}

sync_model_bucket() {
  local bucket="$1"
  local local_dir="$COMFYUI_ROOT/models/$bucket"
  local default_remote_dir="$R2_REMOTE/models/$bucket"
  local cold_remote_dir="$R2_COLD_REMOTE/$bucket"
  local default_list
  local cold_list

  if [ ! -d "$local_dir" ]; then
    log "[SKIP] model dir not found: $local_dir"
    return 0
  fi

  default_list="$(mktemp)"
  cold_list="$(mktemp)"
  trap 'rm -f "$default_list" "$cold_list"' RETURN

  log "[INFO] Scanning remote default model layer: $default_remote_dir"
  list_remote_files "$default_remote_dir" "$default_list"

  log "[INFO] Scanning remote cold model layer: $cold_remote_dir"
  list_remote_files "$cold_remote_dir" "$cold_list"

  log "[INFO] Classifying local models: $local_dir"

  while IFS= read -r -d '' src_file; do
    local filename
    filename="$(basename "$src_file")"

    if remote_file_exists_in_list "$cold_list" "$filename"; then
      log "[SKIP][COLD] $bucket/$filename already exists in cold layer; do not upload to default layer"
      continue
    fi

    if remote_file_exists_in_list "$default_list" "$filename"; then
      log "[COPY][MODEL][DEFAULT] $bucket/$filename -> $default_remote_dir/"
      copy_model_file "$src_file" "$default_remote_dir/$filename"
      continue
    fi

    log "[COPY][MODEL][NEW_TO_COLD] $bucket/$filename -> $cold_remote_dir/"
    copy_model_file "$src_file" "$cold_remote_dir/$filename"
  done < <(find "$local_dir" -maxdepth 1 -type f -print0)

  rm -f "$default_list" "$cold_list"
  trap - RETURN
}

sync_models_misc() {
  local src="$COMFYUI_ROOT/models"
  local dst="$R2_REMOTE/models"

  if [ ! -d "$src" ]; then
    log "[SKIP] dir not found: $src"
    return 0
  fi

  log "[COPY][ADDITIVE] models misc -> $dst/ excluding loras/checkpoints"
  core_rclone_copy "$src" "$dst" \
    "${COMMON_EXCLUDES[@]}" \
    "${MODEL_MISC_EXCLUDES[@]}" \
    --transfers 8 \
    --checkers 16 \
    --fast-list \
    --progress \
    --log-file "$LOG_FILE" \
    --log-level INFO \
    "${RCLONE_DRY_RUN_ARGS[@]}"
}

for item in "${SYNC_DIRS[@]}"; do
  sync_dir "$item"
done

sync_models_misc
sync_model_bucket "loras"
sync_model_bucket "checkpoints"

for item in "${SYNC_FILES[@]}"; do
  copy_file "$item"
done

log "============================================================"
log "[OK] EverSpark Forge asset push completed"
log "[INFO] Log: $LOG_FILE"
log "============================================================"
