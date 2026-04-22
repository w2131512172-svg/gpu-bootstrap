#!/usr/bin/env bash
set -euo pipefail

# ===== AI Forge tunnel config =====
CF_TUNNEL_NAME="comfy"

if pgrep -af "cloudflared tunnel run ${CF_TUNNEL_NAME}" >/dev/null; then
  echo "[INFO] stopping tunnel: ${CF_TUNNEL_NAME}"
  pkill -f "cloudflared tunnel run ${CF_TUNNEL_NAME}"
  sleep 2
else
  echo "[INFO] tunnel is not running: ${CF_TUNNEL_NAME}"
  exit 0
fi

if pgrep -af "cloudflared tunnel run ${CF_TUNNEL_NAME}" >/dev/null; then
  echo "[ERROR] tunnel still running"
  pgrep -af "cloudflared tunnel run ${CF_TUNNEL_NAME}"
  exit 1
else
  echo "[OK] tunnel stopped"
fi
