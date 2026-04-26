#!/usr/bin/env bash
set -e

source /root/ollama-forge/config.env

echo "[AI Forge] Starting Open WebUI..."

mkdir -p "$OPEN_WEBUI_DATA"

source /root/ollama-forge/venv/bin/activate

# Stop old Open WebUI process
pkill -f "uvicorn open_webui.main:app" >/dev/null 2>&1 || true
sleep 2

DATA_DIR="$OPEN_WEBUI_DATA" \
OLLAMA_BASE_URL="http://127.0.0.1:11434" \
nohup python -m uvicorn open_webui.main:app \
  --host 0.0.0.0 \
  --port "$OPEN_WEBUI_PORT" \
  > /root/open-webui.log 2>&1 &

echo "[AI Forge] Waiting for Open WebUI..."

for i in {1..60}; do
  if curl -fsS "http://127.0.0.1:${OPEN_WEBUI_PORT}/health" >/dev/null 2>&1; then
    echo "[AI Forge] Open WebUI is ready."
    curl -fsS "http://127.0.0.1:${OPEN_WEBUI_PORT}/health"
    echo
    exit 0
  fi

  if ! pgrep -f "uvicorn open_webui.main:app" >/dev/null; then
    echo "[AI Forge] Open WebUI process exited. Last log:"
    tail -80 /root/open-webui.log
    exit 1
  fi

  sleep 2
done

echo "[AI Forge] Open WebUI did not become ready in time. Last log:"
tail -80 /root/open-webui.log
exit 1
