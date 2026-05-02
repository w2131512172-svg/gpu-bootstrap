#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

COMFY_ROOT="${COMFY_ROOT:-/root/ComfyUI}"
PORT="${CF_LOCAL_PORT:-8188}"
HOST="${CF_HOSTNAME:-comfy.jhinforge.xyz}"

export CF_TUNNEL_UUID="${CF_TUNNEL_UUID:-4515b24f-a792-485b-b138-940ccb52cefd}"
export CF_HOSTNAME="${CF_HOSTNAME:-$HOST}"
export CF_LOCAL_PORT="${CF_LOCAL_PORT:-$PORT}"

echo "== [AI Forge] start all =="

echo "[0/3] cleaning old wrong processes..."
pkill -f "python -m http.server.*${PORT}" 2>/dev/null || true
pkill -f "http.server" 2>/dev/null || true
pkill -f "cloudflared tunnel run" 2>/dev/null || true
sleep 1

echo "[1/3] checking port ${PORT}..."
if lsof -i :"${PORT}" >/tmp/ai_forge_port_${PORT}.log 2>&1; then
  echo "[WARN] port ${PORT} is occupied:"
  cat /tmp/ai_forge_port_${PORT}.log

  if grep -q "ComfyUI\|main.py\|python" /tmp/ai_forge_port_${PORT}.log; then
    echo "[INFO] killing existing python process on port ${PORT}..."
    lsof -ti :"${PORT}" | xargs -r kill
    sleep 2
  fi
fi

if lsof -i :"${PORT}" >/dev/null 2>&1; then
  echo "[ERROR] port ${PORT} still occupied:"
  lsof -i :"${PORT}"
  exit 1
fi

echo "[2/3] starting ComfyUI on port ${PORT}..."
cd "${COMFY_ROOT}"
nohup python main.py --listen 0.0.0.0 --port "${PORT}" > /root/ComfyUI/user/comfyui.log 2>&1 &

for i in $(seq 1 30); do
  if curl -fsS "http://127.0.0.1:${PORT}" >/dev/null 2>&1; then
    echo "[OK] ComfyUI running on port ${PORT}"
    break
  fi

  if ! pgrep -f "python main.py.*--port ${PORT}" >/dev/null; then
    echo "[ERROR] ComfyUI process exited"
    tail -n 120 /root/ComfyUI/user/comfyui.log
    exit 1
  fi

  sleep 1
done

if ! curl -fsS "http://127.0.0.1:${PORT}" >/dev/null 2>&1; then
  echo "[ERROR] ComfyUI healthcheck failed"
  tail -n 120 /root/ComfyUI/user/comfyui.log
  exit 1
fi

echo "[3/3] starting tunnel..."
cd /root/gpu-bootstrap/comfyui/tunnel
./start_tunnel.sh

echo "[OK] AI Forge ready: https://${CF_HOSTNAME}"
