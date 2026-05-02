#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   bash push_incremental.sh             # dry-run by default
#   bash push_incremental.sh --apply     # real sync/copy
#
# Strategy:
#   1) ComfyUI core: sync with deletes, but exclude assets/runtime dirs
#   2) assets dirs: copy only, no deletes
#   3) custom_nodes: sync with deletes, but only if changed

APPLY=0
if [[ "${1:-}" == "--apply" ]]; then
  APPLY=1
fi

DRY_RUN_ARGS=(--dry-run)
if [[ "$APPLY" -eq 1 ]]; then
  DRY_RUN_ARGS=()
  echo "[MODE] APPLY: real upload/sync will be executed"
else
  echo "[MODE] DRY-RUN: no remote changes will be made"
  echo "[HINT] Run with --apply after reviewing logs"
fi

# ===== rclone config self-check =====
RCLONE_CONF_SRC="/root/rclone.conf"
RCLONE_CONF_DST="/root/.config/rclone/rclone.conf"

if [[ -f "$RCLONE_CONF_SRC" ]]; then
  if [[ ! -f "$RCLONE_CONF_DST" ]]; then
    echo "[INFO] installing rclone config..."
    mkdir -p /root/.config/rclone
    cp "$RCLONE_CONF_SRC" "$RCLONE_CONF_DST"
    echo "[OK] rclone config installed"
  fi
else
  echo "[WARN] /root/rclone.conf not found"
fi

# ===== paths =====
ROOT_SRC="/root/ComfyUI"
ROOT_DST="r2-assets:comfyui-assets/ComfyUI"

CN_SRC="$ROOT_SRC/custom_nodes"
CN_DST="$ROOT_DST/custom_nodes"

LOG_DIR="/root"
LOG_CORE="$LOG_DIR/rclone_sync_comfyui_core.log"
LOG_ASSETS="$LOG_DIR/rclone_copy_comfyui_assets.log"
LOG_CN="$LOG_DIR/rclone_sync_custom_nodes.log"

COMMON_ARGS=(
  --progress
  --stats=10s
  --transfers=8
  --checkers=16
  --fast-list
  --log-level INFO
)

if [[ ! -d "$ROOT_SRC" ]]; then
  echo "[ERROR] Cannot find local ComfyUI directory at $ROOT_SRC"
  exit 1
fi

echo "[INFO] Local ComfyUI:  $ROOT_SRC"
echo "[INFO] Remote ComfyUI: $ROOT_DST"

# ===== 1) ComfyUI core: sync with deletes =====
# Sync official ComfyUI code/runtime skeleton, but never touch large/user/plugin dirs.
echo "[CORE] Sync ComfyUI core with deletes, excluding assets/runtime dirs..."

rclone sync "$ROOT_SRC" "$ROOT_DST" \
  --exclude "/.git/**" \
  --exclude "/custom_nodes/**" \
  --exclude "/models/**" \
  --exclude "/output/**" \
  --exclude "/input/**" \
  --exclude "/user/**" \
  --exclude "/temp/**" \
  --exclude "/.cache/**" \
  --exclude "/__pycache__/**" \
  --exclude "**/__pycache__/**" \
  --exclude "*.pyc" \
  --exclude "*.pyo" \
  --exclude ".DS_Store" \
  "${DRY_RUN_ARGS[@]}" \
  "${COMMON_ARGS[@]}" \
  --log-file="$LOG_CORE"

echo "[CORE] Done. Log: $LOG_CORE"

# ===== 2) Assets: copy only, no deletes =====
# These are user/data directories. Never delete remote files from here automatically.
echo "[ASSETS] Copy selected asset/user dirs only, no deletes..."

for dir in models input user; do
  SRC="$ROOT_SRC/$dir"
  DST="$ROOT_DST/$dir"

  if [[ -d "$SRC" ]]; then
    echo "[ASSETS] copy $dir ..."
    rclone copy "$SRC" "$DST" \
      --exclude "/__pycache__/**" \
      --exclude "**/__pycache__/**" \
      --exclude "*.pyc" \
      --exclude "*.pyo" \
      --exclude ".DS_Store" \
      "${DRY_RUN_ARGS[@]}" \
      "${COMMON_ARGS[@]}" \
      --log-file="$LOG_ASSETS"
  else
    echo "[ASSETS] skip missing dir: $SRC"
  fi
done

echo "[ASSETS] Done. Log: $LOG_ASSETS"

# ===== 3) custom_nodes: sync with deletes, only if changed =====
if [[ ! -d "$CN_SRC" ]]; then
  echo "[WARN] $CN_SRC not found, skip custom_nodes sync."
  exit 0
fi

STATE_DIR="/root/.rclone_state"
mkdir -p "$STATE_DIR"
STATE_FILE="$STATE_DIR/custom_nodes.sha256"

NEW_HASH="$(find "$CN_SRC" -type f \
  ! -path "*/.git/*" \
  ! -path "*/__pycache__/*" \
  ! -name "*.pyc" \
  ! -name "*.pyo" \
  -printf '%p|%s|%T@\n' 2>/dev/null | sort | sha256sum | awk '{print $1}')"

OLD_HASH=""
if [[ -f "$STATE_FILE" ]]; then
  OLD_HASH="$(cat "$STATE_FILE" || true)"
fi

if [[ "$NEW_HASH" != "$OLD_HASH" || "$APPLY" -eq 0 ]]; then
  echo "[custom_nodes] Change detected or dry-run mode -> syncing with deletes..."

  rclone sync "$CN_SRC" "$CN_DST" \
    --exclude "/.git/**" \
    --exclude "**/.git/**" \
    --exclude "/__pycache__/**" \
    --exclude "**/__pycache__/**" \
    --exclude "*.pyc" \
    --exclude "*.pyo" \
    --exclude ".DS_Store" \
    "${DRY_RUN_ARGS[@]}" \
    "${COMMON_ARGS[@]}" \
    --log-file="$LOG_CN"

  if [[ "$APPLY" -eq 1 ]]; then
    echo "$NEW_HASH" > "$STATE_FILE"
  fi

  echo "[custom_nodes] Done. Log: $LOG_CN"
else
  echo "[custom_nodes] No change -> skip sync."
fi

echo "[DONE] push_incremental completed."

