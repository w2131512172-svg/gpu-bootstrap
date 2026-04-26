#!/usr/bin/env bash
set -e

echo "[AI Forge] Starting all services..."

# ===== Start Ollama =====
if ! pgrep -x "ollama" >/dev/null; then
  echo "[AI Forge] Starting Ollama..."
  nohup ollama serve > /root/ollama.log 2>&1 &
  sleep 5
else
  echo "[AI Forge] Ollama already running."
fi

echo "[AI Forge] Checking Ollama..."
ollama list >/dev/null
echo "[AI Forge] Ollama OK."

# ===== Start Open WebUI =====
bash /root/ollama-forge/start_open_webui.sh

echo "[AI Forge] All services started."
