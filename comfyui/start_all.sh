#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ===== load global env =====
if [ -f /root/.env ]; then
  echo "[INFO] loading /root/.env"
  set -a
  source /root/.env
  set +a
fi

# ===== defaults =====
export CF_TUNNEL_UUID="${CF_TUNNEL_UUID:-4515b24f-a792-485b-b138-940ccb52cefd}"
export CF_HOSTNAME="${CF_HOSTNAME:-comfy.jhinforge.xyz}"
export CF_LOCAL_PORT="${CF_LOCAL_PORT:-8188}"
export CF_TUNNEL_NAME="${CF_TUNNEL_NAME:-comfy}"

COMFY_DIR="${COMFY_DIR:-/root/ComfyUI}"
LOG_DIR="${AI_FORGE_LOG_DIR:-/root/ai_forge_logs}"
SERVICE_LOG="${SERVICE_LOG:-${LOG_DIR}/comfyui.log}"
START_LOG="${START_LOG:-${LOG_DIR}/start_all.log}"

mkdir -p "$LOG_DIR"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$START_LOG"
}

die() {
  log "[ERROR] $*"
  exit 1
}

usage() {
  cat <<EOF
Usage: bash start_all.sh [start|stop|restart|status]

Commands:
  start     Start ComfyUI and Cloudflare Tunnel. Default.
  stop      Stop ComfyUI only.
  restart   Restart ComfyUI only, then keep/start tunnel.
  status    Show ComfyUI/tunnel process and port status.
EOF
}

kill_wrong_services() {
  log "[0/3] cleaning wrong services..."
  pkill -f "python -m http.server" 2>/dev/null || true
  pkill -f "http.server" 2>/dev/null || true
}

is_comfy_running() {
  curl -fsS "http://127.0.0.1:${CF_LOCAL_PORT}" >/dev/null 2>&1 \
    && pgrep -f "main.py.*--port ${CF_LOCAL_PORT}" >/dev/null 2>&1
}

stop_comfy() {
  log "[INFO] stopping ComfyUI on port ${CF_LOCAL_PORT}..."

  if pgrep -f "main.py.*--port ${CF_LOCAL_PORT}" >/dev/null 2>&1; then
    pkill -f "main.py.*--port ${CF_LOCAL_PORT}" 2>/dev/null || true
    sleep 2
  fi

  if lsof -ti :"${CF_LOCAL_PORT}" >/dev/null 2>&1; then
    log "[WARN] port ${CF_LOCAL_PORT} still occupied, killing port owner..."
    lsof -ti :"${CF_LOCAL_PORT}" | xargs -r kill 2>/dev/null || true
    sleep 2
  fi

  if pgrep -f "main.py.*--port ${CF_LOCAL_PORT}" >/dev/null 2>&1; then
    log "[WARN] ComfyUI still alive, force killing..."
    pkill -9 -f "main.py.*--port ${CF_LOCAL_PORT}" 2>/dev/null || true
    sleep 1
  fi

  if pgrep -f "main.py.*--port ${CF_LOCAL_PORT}" >/dev/null 2>&1; then
    die "failed to stop ComfyUI"
  fi

  log "[OK] ComfyUI stopped"
}

start_comfy() {
  kill_wrong_services

  if lsof -i :"${CF_LOCAL_PORT}" >/tmp/ai_forge_port.log 2>&1; then
    log "[WARN] port ${CF_LOCAL_PORT} occupied:"
    cat /tmp/ai_forge_port.log | tee -a "$START_LOG"

    if ! pgrep -f "main.py.*--port ${CF_LOCAL_PORT}" >/dev/null 2>&1; then
      log "[INFO] killing non-ComfyUI process on port ${CF_LOCAL_PORT}..."
      lsof -ti :"${CF_LOCAL_PORT}" | xargs -r kill
      sleep 2
    fi
  fi

  log "[1/3] starting ComfyUI..."

  if is_comfy_running; then
    log "[OK] ComfyUI already running on port ${CF_LOCAL_PORT}"
    return 0
  fi

  [ -d "$COMFY_DIR" ] || die "COMFY_DIR not found: $COMFY_DIR"
  [ -f "$COMFY_DIR/main.py" ] || die "ComfyUI main.py not found: $COMFY_DIR/main.py"

  cd "$COMFY_DIR"
  mkdir -p "$(dirname "$SERVICE_LOG")"

  nohup python main.py --listen 0.0.0.0 --port "${CF_LOCAL_PORT}" \
    > "$SERVICE_LOG" 2>&1 &

  for _ in $(seq 1 30); do
    if curl -fsS "http://127.0.0.1:${CF_LOCAL_PORT}" >/dev/null 2>&1; then
      log "[OK] ComfyUI running on port ${CF_LOCAL_PORT}"
      return 0
    fi

    if ! pgrep -f "main.py.*--port ${CF_LOCAL_PORT}" >/dev/null 2>&1; then
      log "[ERROR] ComfyUI exited"
      tail -n 120 "$SERVICE_LOG" | tee -a "$START_LOG" || true
      exit 1
    fi

    sleep 1
  done

  log "[ERROR] ComfyUI healthcheck failed"
  tail -n 120 "$SERVICE_LOG" | tee -a "$START_LOG" || true
  exit 1
}

start_tunnel() {
  log "[2/3] starting tunnel..."
  bash "${SCRIPT_DIR}/tunnel/start_tunnel.sh" 2>&1 | tee -a "$START_LOG"
}

status_all() {
  log "[INFO] status"
  log "[INFO] hostname: ${CF_HOSTNAME}"
  log "[INFO] port: ${CF_LOCAL_PORT}"
  log "[INFO] ComfyUI log: ${SERVICE_LOG}"
  log "[INFO] start log: ${START_LOG}"

  if is_comfy_running; then
    log "[OK] ComfyUI HTTP healthcheck passed"
  else
    log "[WARN] ComfyUI HTTP healthcheck not ready"
  fi

  lsof -i :"${CF_LOCAL_PORT}" 2>&1 | tee -a "$START_LOG" || true
  pgrep -af "main.py|cloudflared|http.server" 2>&1 | tee -a "$START_LOG" || true
}

start_all() {
  log "== [AI Forge] start all =="
  log "[INFO] hostname: ${CF_HOSTNAME}"
  log "[INFO] port: ${CF_LOCAL_PORT}"
  log "[INFO] ComfyUI log: ${SERVICE_LOG}"

  start_comfy
  start_tunnel

  log "[3/3] final check..."
  status_all

  log "========================================"
  log "[SUCCESS] AI Forge is ONLINE 🚀"
  log "👉 https://${CF_HOSTNAME}"
  log "========================================"
}

cmd="${1:-start}"

case "$cmd" in
  start)
    start_all
    ;;
  stop)
    stop_comfy
    ;;
  restart)
    stop_comfy
    start_comfy
    start_tunnel
    status_all
    ;;
  status)
    status_all
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    usage
    die "unknown command: $cmd"
    ;;
esac
