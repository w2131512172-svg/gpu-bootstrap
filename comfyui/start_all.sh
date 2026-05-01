#!/usr/bin/env bash
set -euo pipefail

echo "== [AI Forge] start all =="

# ===== 参数 =====
: "${CF_TUNNEL_UUID:?need CF_TUNNEL_UUID}"
: "${CF_HOSTNAME:?need CF_HOSTNAME}"
: "${CF_LOCAL_PORT:=8188}"

COMFY_DIR="/root/ComfyUI"
SERVICE_LOG="/root/comfyui.log"

# ===== 1. 启动 ComfyUI =====
echo "[1/2] starting ComfyUI..."

if pgrep -f "main.py" >/dev/null; then
  echo "[INFO] ComfyUI already running"
else
  cd "${COMFY_DIR}"
  nohup python main.py --listen 0.0.0.0 --port "${CF_LOCAL_PORT}" \
    > "${SERVICE_LOG}" 2>&1 &
  sleep 5
fi

# ===== 检查服务 =====
if pgrep -f "main.py" >/dev/null; then
  echo "[OK] ComfyUI running on port ${CF_LOCAL_PORT}"
else
  echo "[ERROR] ComfyUI failed"
  tail -n 50 "${SERVICE_LOG}" || true
  exit 1
fi

# ===== 2. 启动 tunnel =====
echo "[2/2] starting tunnel..."
bash "$(dirname "$0")/tunnel/start_tunnel.sh"

echo "========================================"
echo "[SUCCESS] AI Forge is ONLINE 🚀"
echo "👉 https://${CF_HOSTNAME}"
echo "========================================"
