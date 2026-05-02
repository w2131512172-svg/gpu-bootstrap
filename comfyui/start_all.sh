#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ===== 加载全局环境变量 =====
if [ -f /root/.env ]; then
  echo "[INFO] loading /root/.env"
  set -a
  source /root/.env
  set +a
fi

echo "== [AI Forge] start all =="

# ===== defaults =====
export CF_TUNNEL_UUID="${CF_TUNNEL_UUID:-4515b24f-a792-485b-b138-940ccb52cefd}"
export CF_HOSTNAME="${CF_HOSTNAME:-comfy.jhinforge.xyz}"
export CF_LOCAL_PORT="${CF_LOCAL_PORT:-8188}"

COMFY_DIR="${COMFY_DIR:-/root/ComfyUI}"
SERVICE_LOG="${SERVICE_LOG:-/root/comfyui.log}" 

echo "[INFO] hostname: ${CF_HOSTNAME}"
echo "[INFO] port: ${CF_LOCAL_PORT}"

# ===== 0. 清理错误服务 =====
echo "[0/3] cleaning wrong services..."

pkill -f "python -m http.server" 2>/dev/null || true
pkill -f "http.server" 2>/dev/null || true

if lsof -i :"${CF_LOCAL_PORT}" >/tmp/ai_forge_port.log 2>&1; then
  echo "[WARN] port ${CF_LOCAL_PORT} occupied:"
  cat /tmp/ai_forge_port.log

  if ! pgrep -f "main.py.*--port ${CF_LOCAL_PORT}" >/dev/null; then
    echo "[INFO] killing process on port ${CF_LOCAL_PORT}..."
    lsof -ti :"${CF_LOCAL_PORT}" | xargs -r kill
    sleep 2
  fi
fi

# ===== 1. 启动 ComfyUI =====
echo "[1/3] starting ComfyUI..."

if curl -fsS "http://127.0.0.1:${CF_LOCAL_PORT}" >/dev/null 2>&1 \
   && pgrep -f "main.py.*--port ${CF_LOCAL_PORT}" >/dev/null; then
  echo "[OK] ComfyUI already running on port ${CF_LOCAL_PORT}"
else
  cd "${COMFY_DIR}"
  mkdir -p "$(dirname "${SERVICE_LOG}")"

  nohup python main.py --listen 0.0.0.0 --port "${CF_LOCAL_PORT}" \
    > "${SERVICE_LOG}" 2>&1 &

  for i in $(seq 1 30); do
    if curl -fsS "http://127.0.0.1:${CF_LOCAL_PORT}" >/dev/null 2>&1; then
      echo "[OK] ComfyUI running on port ${CF_LOCAL_PORT}"
      break
    fi

    if ! pgrep -f "main.py.*--port ${CF_LOCAL_PORT}" >/dev/null; then
      echo "[ERROR] ComfyUI exited"
      tail -n 120 "${SERVICE_LOG}" || true
      exit 1
    fi

    sleep 1
  done
fi

if ! curl -fsS "http://127.0.0.1:${CF_LOCAL_PORT}" >/dev/null 2>&1; then
  echo "[ERROR] ComfyUI healthcheck failed"
  tail -n 120 "${SERVICE_LOG}" || true
  exit 1
fi

# ===== 2. 启动 tunnel =====
echo "[2/3] starting tunnel..."
bash "${SCRIPT_DIR}/tunnel/start_tunnel.sh"

echo "[3/3] final check..."
lsof -i :"${CF_LOCAL_PORT}" || true
pgrep -af "main.py|http.server|cloudflared" || true

echo "========================================"
echo "[SUCCESS] AI Forge is ONLINE 🚀"
echo "👉 https://${CF_HOSTNAME}"
echo "========================================"
