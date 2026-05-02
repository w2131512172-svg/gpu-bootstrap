#!/usr/bin/env bash
set -euo pipefail

# ===== rclone 配置自检 =====
RCLONE_CONF_SRC="/root/rclone.conf"
RCLONE_CONF_DST="/root/.config/rclone/rclone.conf"

if [ -f "${RCLONE_CONF_SRC}" ]; then
  if [ ! -f "${RCLONE_CONF_DST}" ]; then
    echo "[INFO] installing rclone config..."
    mkdir -p /root/.config/rclone
    cp "${RCLONE_CONF_SRC}" "${RCLONE_CONF_DST}"
    echo "[OK] rclone config installed"
  fi
else
  echo "[WARN] /root/rclone.conf not found"
fi

SRC="r2-assets:comfyui-assets/ComfyUI"
DST="/root/ComfyUI"

mkdir -p "$DST"

rclone copy "$SRC" "$DST" \
  --exclude "/output/**" \
  --progress \
  --stats=10s \
  --transfers=8 \
  --checkers=16 \
  --fast-list \
  --create-empty-src-dirs \
  --log-file="/root/rclone_pull_from_r2.log" \
  --log-level INFO
