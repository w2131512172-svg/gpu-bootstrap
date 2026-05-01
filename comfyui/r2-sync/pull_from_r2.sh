#!/usr/bin/env bash
set -euo pipefail

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
