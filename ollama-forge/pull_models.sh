#!/usr/bin/env bash
set -e

MODELS_FILE="/root/ollama-forge/models.txt"

echo "[AI Forge] Pulling Ollama models..."

if ! pgrep -x "ollama" >/dev/null; then
  echo "[AI Forge] Ollama is not running, starting..."
  nohup ollama serve > /root/ollama.log 2>&1 &
  sleep 5
fi

while IFS= read -r model; do
  # 跳过空行和注释
  [[ -z "$model" ]] && continue
  [[ "$model" =~ ^# ]] && continue

  echo "[AI Forge] Checking model: $model"

  if ollama list | awk '{print $1}' | grep -qx "$model"; then
    echo "[AI Forge] Model already exists, skip: $model"
  else
    echo "[AI Forge] Pulling model: $model"
    ollama pull "$model"
  fi
done < "$MODELS_FILE"

echo "[AI Forge] Model pull complete."
ollama list
