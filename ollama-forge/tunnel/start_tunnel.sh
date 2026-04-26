#!/usr/bin/env bash
set -euo pipefail

: "${CF_TUNNEL_NAME:=comfy}"

echo "[INFO] rendering config..."
bash "$(dirname "$0")/render_tunnel_config.sh"

echo "[INFO] starting tunnel: ${CF_TUNNEL_NAME}"

nohup cloudflared tunnel run "${CF_TUNNEL_NAME}" \
  > /root/cloudflared.log 2>&1 &

sleep 2

if pgrep -af "cloudflared tunnel run ${CF_TUNNEL_NAME}" >/dev/null; then
  echo "[OK] tunnel started"
  echo "[INFO] log: /root/cloudflared.log"
else
  echo "[ERROR] tunnel failed"
  tail -n 50 /root/cloudflared.log || true
  exit 1
fi
