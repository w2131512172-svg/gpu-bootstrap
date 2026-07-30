#!/usr/bin/env bash
set -euo pipefail

# ===== load env =====
if [ -f /root/.env ]; then
  echo "[OK] env exists: /root/.env"
  set -a
  source /root/.env
  set +a
else
  echo "[ERROR] env missing: /root/.env"
  exit 1
fi

: "${CF_TUNNEL_UUID:?need CF_TUNNEL_UUID}"
: "${CF_HOSTNAME:?need CF_HOSTNAME}"
: "${CF_LOCAL_PORT:?need CF_LOCAL_PORT}"

LOG_DIR="${AI_FORGE_LOG_DIR:-/root/ai_forge_logs}"
CLOUDFLARED_LOG="${CLOUDFLARED_LOG:-${LOG_DIR}/cloudflared.log}"
TUNNEL_CHECK_LOG="${TUNNEL_CHECK_LOG:-${LOG_DIR}/tunnel_check.log}"

CONFIG_FILE="/root/.cloudflared/config.yml"
CRED_FILE="/root/.cloudflared/${CF_TUNNEL_UUID}.json"

mkdir -p "$LOG_DIR"

exec > >(tee -a "$TUNNEL_CHECK_LOG") 2>&1

echo "============================================================"
echo "[INFO] AI Forge tunnel check"
echo "[INFO] hostname : $CF_HOSTNAME"
echo "[INFO] local port: $CF_LOCAL_PORT"
echo "[INFO] uuid      : $CF_TUNNEL_UUID"
echo "============================================================"

command -v cloudflared >/dev/null 2>&1 \
  && echo "[OK] cloudflared found: $(command -v cloudflared)" \
  || { echo "[ERROR] cloudflared not found"; exit 1; }

[ -f "$CONFIG_FILE" ] \
  && echo "[OK] config exists: $CONFIG_FILE" \
  || { echo "[ERROR] config missing: $CONFIG_FILE"; exit 1; }

[ -f "$CRED_FILE" ] \
  && echo "[OK] credential exists: $CRED_FILE" \
  || { echo "[ERROR] credential missing: $CRED_FILE"; exit 1; }

if pgrep -af "cloudflared" | grep -q "$CONFIG_FILE"; then
  echo "[OK] tunnel process running"
  pgrep -af "cloudflared" || true
else
  echo "[ERROR] tunnel process not running"
  exit 1
fi

if curl -fsS "http://127.0.0.1:${CF_LOCAL_PORT}" >/dev/null 2>&1; then
  echo "[OK] local service reachable: 127.0.0.1:${CF_LOCAL_PORT}"
else
  echo "[WARN] local service not reachable: 127.0.0.1:${CF_LOCAL_PORT}"
fi

if [ -f "$CLOUDFLARED_LOG" ]; then
  echo "[OK] cloudflared log exists: $CLOUDFLARED_LOG"

  if grep -q "Registered tunnel connection" "$CLOUDFLARED_LOG"; then
    echo "[OK] tunnel registered with Cloudflare"
  else
    echo "[WARN] no registered tunnel connection found in log"
  fi

  echo "----------------------------------------"
  tail -n 30 "$CLOUDFLARED_LOG" || true
else
  echo "[WARN] cloudflared log not found: $CLOUDFLARED_LOG"
fi

echo "============================================================"
echo "[OK] tunnel check completed"
echo "============================================================"
