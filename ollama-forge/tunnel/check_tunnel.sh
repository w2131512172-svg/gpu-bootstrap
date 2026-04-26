#!/usr/bin/env bash
set -euo pipefail

# ===== AI Forge tunnel config =====
CF_TUNNEL_NAME="comfy"
CF_TUNNEL_UUID="4515b24f-a792-485b-b138-940ccb52cefd"
CF_HOSTNAME="comfy.jhinforge.xyz"
CF_LOCAL_PORT="3000"

LOG_FILE="/root/cloudflared.log"

echo "[INFO] tunnel name : $CF_TUNNEL_NAME"
echo "[INFO] hostname    : $CF_HOSTNAME"
echo "[INFO] local port  : $CF_LOCAL_PORT"

if pgrep -af "cloudflared tunnel run ${CF_TUNNEL_NAME}" >/dev/null; then
  echo "[OK] tunnel process is running"
  pgrep -af "cloudflared tunnel run ${CF_TUNNEL_NAME}"
else
  echo "[ERROR] tunnel process is not running"
  exit 1
fi

if [ -f "$LOG_FILE" ]; then
  echo "[OK] log file exists: $LOG_FILE"
  echo "----------------------------------------"
  tail -n 20 "$LOG_FILE" || true
else
  echo "[WARN] log file not found: $LOG_FILE"
fi
