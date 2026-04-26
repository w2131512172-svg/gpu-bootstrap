#!/usr/bin/env bash
set -e

source /root/ollama-forge/config.env

echo "[AI Forge] Restoring Ollama data from R2..."

# 创建目录
mkdir -p /root/.ollama

# 拉取数据
rclone copy r2-assets:ollama-forge/.ollama /root/.ollama \
  --progress \
  --transfers=8 \
  --checkers=8 \
  --fast-list \
  --log-file=/root/rclone_restore.log

echo "[AI Forge] Restore complete."

# 检查
echo "[AI Forge] Verifying..."
ollama list

echo "[AI Forge] Done."
