#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

# ===== load env =====
if [ -f /root/.env ]; then
  set -a
  source /root/.env
  set +a
else
  echo "[WARN] /root/.env not found"
fi

: "${CF_TUNNEL_UUID:?need CF_TUNNEL_UUID}"
: "${CF_HOSTNAME:?need CF_HOSTNAME}"
: "${CF_LOCAL_PORT:?need CF_LOCAL_PORT}"
: "${CF_TUNNEL_NAME:=comfy}"

LOG_DIR="${AI_FORGE_LOG_DIR:-/root/ai_forge_logs}"
CLOUDFLARED_LOG="${CLOUDFLARED_LOG:-${LOG_DIR}/cloudflared.log}"

CONFIG_FILE="/root/.cloudflared/config.yml"
CRED_SRC="/root/${CF_TUNNEL_UUID}.json"
CRED_DST="/root/.cloudflared/${CF_TUNNEL_UUID}.json"

mkdir -p "$LOG_DIR"
mkdir -p /root/.cloudflared

export CF_TUNNEL_UUID CF_HOSTNAME CF_LOCAL_PORT CF_TUNNEL_NAME

echo "[INFO] stopping old cloudflared..."
pkill -9 -f "cloudflared" 2>/dev/null || true
sleep 2

echo "[INFO] installing tunnel credential..."
if [ ! -f "$CRED_DST" ]; then
  if [ -f "$CRED_SRC" ]; then
    cp "$CRED_SRC" "$CRED_DST"
    chmod 600 "$CRED_DST"
    echo "[OK] credential installed: $CRED_DST"
  else
    echo "[ERROR] tunnel credential not found:"
    echo "  expected: $CRED_DST"
    echo "  or upload to: $CRED_SRC"
    exit 1
  fi
else
  chmod 600 "$CRED_DST"
  echo "[OK] credential exists: $CRED_DST"
fi

echo "[INFO] rendering config..."
./render_tunnel_config.sh

echo "[INFO] starting tunnel: ${CF_TUNNEL_NAME}"
nohup cloudflared tunnel --config "$CONFIG_FILE" run \
  > "$CLOUDFLARED_LOG" 2>&1 &

sleep 3

if pgrep -af "cloudflared" | grep -q "$CONFIG_FILE"; then
  echo "[OK] tunnel process running"
else
  echo "[ERROR] tunnel process failed"
  tail -n 80 "$CLOUDFLARED_LOG" || true
  exit 1
fi

if grep -q "Registered tunnel connection" "$CLOUDFLARED_LOG"; then
  echo "[OK] tunnel registered with Cloudflare"
else
  echo "[WARN] tunnel process exists, but no registered connection found yet"
  tail -n 80 "$CLOUDFLARED_LOG" || true
fi
