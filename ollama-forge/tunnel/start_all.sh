#!/usr/bin/env bash
set -euo pipefail

echo "== [AI Forge] start all =="

# ===== 参数默认值 =====
: "${CF_TUNNEL_UUID:?need CF_TUNNEL_UUID}"
: "${CF_HOSTNAME:?need CF_HOSTNAME}"
: "${CF_LOCAL_PORT:=3000}"

# ===== 1. 启动服务（这里先用最小 http server）=====
echo "[1/2] starting service on port ${CF_LOCAL_PORT}..."

if pgrep -f "http.server ${CF_LOCAL_PORT}" >/dev/null; then
  echo "[INFO] service already running"
else
  nohup python3 -m http.server "${CF_LOCAL_PORT}" \
    > /root/service.log 2>&1 &
  sleep 2
fi

# ===== 检查服务 =====
if ss -ltnp | grep -q ":${CF_LOCAL_PORT}"; then
  echo "[OK] service running on port ${CF_LOCAL_PORT}"
else
  echo "[ERROR] service failed"
  tail -n 50 /root/service.log || true
  exit 1
fi

# ===== 2. 启动 tunnel =====
echo "[2/2] starting tunnel..."
bash "$(dirname "$0")/tunnel/start_tunnel.sh"

echo "========================================"
echo "[SUCCESS] AI Forge is ONLINE 🚀"
echo "👉 https://${CF_HOSTNAME}"
echo "========================================"
