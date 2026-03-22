#!/usr/bin/env bash
set -euo pipefail

# ====== Remote (R2) fixed ======
ROOT_DST="r2-assets:comfyui-assets/ComfyUI"
CN_DST="$ROOT_DST/custom_nodes"

# ====== Detect local ComfyUI root ======
if [[ -d "/root/ComfyUI" ]]; then
  ROOT_SRC="/root/ComfyUI"
elif [[ -d "/workspace/ComfyUI" ]]; then
  ROOT_SRC="/workspace/ComfyUI"
else
  echo "[ERROR] Cannot find local ComfyUI directory at /root/ComfyUI or /workspace/ComfyUI"
  echo "        Please set ROOT_SRC manually in this script."
  exit 1
fi

CN_SRC="$ROOT_SRC/custom_nodes"

LOG_COPY="/root/rclone_push_incremental.log"
LOG_SYNC="/root/rclone_sync_custom_nodes.log"

echo "[INFO] Local ComfyUI: $ROOT_SRC"
echo "[INFO] Remote ComfyUI: $ROOT_DST"

# 1) Global: copy only (no deletes), exclude output + exclude custom_nodes
rclone copy "$ROOT_SRC" "$ROOT_DST" \
  --exclude "/output/**" \
  --exclude "/custom_nodes/**" \
  --progress \
  --stats=10s \
  --transfers=8 \
  --checkers=16 \
  --fast-list \
  --log-file="$LOG_COPY" \
  --log-level INFO

# 2) custom_nodes: sync with delete, but only if changed
if [[ ! -d "$CN_SRC" ]]; then
  echo "[WARN] $CN_SRC not found, skip custom_nodes sync."
  exit 0
fi

STATE_DIR="/root/.rclone_state"
mkdir -p "$STATE_DIR"
STATE_FILE="$STATE_DIR/custom_nodes.sha256"

NEW_HASH="$(find "$CN_SRC" -type f -printf '%p|%s|%T@\n' 2>/dev/null | sort | sha256sum | awk '{print $1}')"
OLD_HASH=""
if [[ -f "$STATE_FILE" ]]; then
  OLD_HASH="$(cat "$STATE_FILE" || true)"
fi

if [[ "$NEW_HASH" != "$OLD_HASH" ]]; then
  echo "[custom_nodes] Change detected -> syncing (with deletes)..."
  rclone sync "$CN_SRC" "$CN_DST" \
    --progress \
    --stats=10s \
    --transfers=8 \
    --checkers=16 \
    --fast-list \
    --log-file="$LOG_SYNC" \
    --log-level INFO
  echo "$NEW_HASH" > "$STATE_FILE"
  echo "[custom_nodes] Sync done."
else
  echo "[custom_nodes] No change -> skip sync."
fi
