#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

: "${CF_TUNNEL_UUID:=4515b24f-a792-485b-b138-940ccb52cefd}"
: "${CF_HOSTNAME:=comfy.jhinforge.xyz}"
: "${CF_LOCAL_PORT:=8188}"
: "${CF_TUNNEL_NAME:=comfy}"

export CF_TUNNEL_UUID CF_HOSTNAME CF_LOCAL_PORT CF_TUNNEL_NAME

echo "[INFO] stopping old cloudflared..."
pkill -f "cloudflared tunnel run" 2>/dev/null || true
sleep 1

echo "[INFO] rendering config..."
./render_tunnel_config.sh

echo "[INFO] starting tunnel: ${CF_TUNNEL_NAME}"
nohup cloudflared tunnel run "${CF_TUNNEL_NAME}" > /root/cloudflared.log 2>&1 &

sleep 3

if pgrep -f "cloudflared tunnel run" >/dev/null; then
  echo "[OK] tunnel running"
else
  echo "[ERROR] tunnel failed"
  tail -n 80 /root/cloudflared.log
  exit 1
fi
