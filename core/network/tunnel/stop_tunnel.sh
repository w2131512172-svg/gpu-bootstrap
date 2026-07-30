#!/usr/bin/env bash
set -euo pipefail

echo "[INFO] stopping cloudflared tunnel..."

pkill -9 -f "cloudflared" 2>/dev/null || true
sleep 2

if pgrep -af "cloudflared" >/dev/null; then
  echo "[ERROR] tunnel still running"
  pgrep -af "cloudflared" || true
  exit 1
else
  echo "[OK] tunnel stopped"
fi
