#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck disable=SC1091
source "${REPO_ROOT}/core/hardware/gpu_assignment.sh"

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

TORCH_PROFILE="${TORCH_PROFILE:-auto}"
ENV_NAME="${ENV_NAME:-}"
MINICONDA_DIR="${MINICONDA_DIR:-/root/miniconda3}"
COMFY_START_TIMEOUT="${COMFY_START_TIMEOUT:-300}"
COMFY_START_GRACE="${COMFY_START_GRACE:-8}"

COMFY_DIR="${COMFY_DIR:-/root/ComfyUI}"
LOG_DIR="${EVERSPARK_LOG_DIR:-/root/everspark_logs}"
SERVICE_LOG="${SERVICE_LOG:-${LOG_DIR}/comfyui.log}"
START_LOG="${START_LOG:-${LOG_DIR}/start_all.log}"
BOOT_REPAIR_LOG="${BOOT_REPAIR_LOG:-${LOG_DIR}/boot_repair.nohup.log}"
BOOT_REPAIR_SCRIPT="${BOOT_REPAIR_SCRIPT:-${SCRIPT_DIR}/deps/boot_repair.py}"

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
  restart   Restart ComfyUI only. Does not touch Cloudflare Tunnel.
  status    Show ComfyUI/tunnel process and port status.
EOF
}

resolve_env_name() {
  if [ -n "${ENV_NAME:-}" ]; then
    log "[INFO] ENV_NAME provided: ${ENV_NAME}"
    return 0
  fi

  local selected_profile="$TORCH_PROFILE"

  if [ "$selected_profile" = "auto" ]; then
    if [ -x "${SCRIPT_DIR}/detect_torch_profile.sh" ] || [ -f "${SCRIPT_DIR}/detect_torch_profile.sh" ]; then
      selected_profile="$(bash "${SCRIPT_DIR}/detect_torch_profile.sh" | tail -n 1 | tr -d '[:space:]')"
      log "[INFO] detected TORCH_PROFILE for service layer: ${selected_profile}"
    else
      selected_profile="cu121"
      log "[WARN] detect_torch_profile.sh not found; fallback TORCH_PROFILE=${selected_profile}"
    fi
  else
    log "[INFO] TORCH_PROFILE provided for service layer: ${selected_profile}"
  fi

  case "$selected_profile" in
    cu128)
      ENV_NAME="torch-cu128"
      ;;
    cu121)
      ENV_NAME="torch251-cu121"
      ;;
    *)
      die "unsupported TORCH_PROFILE for service layer: ${selected_profile}"
      ;;
  esac

  export TORCH_PROFILE="$selected_profile"
  export ENV_NAME
  log "[INFO] selected conda env for service layer: ${ENV_NAME}"
}

activate_project_env() {
  resolve_env_name
  log "[INFO] activating conda env for service layer: ${ENV_NAME}"

  local conda_sh="${MINICONDA_DIR}/etc/profile.d/conda.sh"

  if [ ! -f "$conda_sh" ]; then
    die "conda.sh not found: $conda_sh"
  fi

  # shellcheck disable=SC1090
  source "$conda_sh"
  conda activate "$ENV_NAME"

  command -v python >/dev/null 2>&1 || die "python not found after conda activate"

  log "[OK] service conda env activated: ${ENV_NAME}"
  log "[INFO] python: $(command -v python)"
  log "[INFO] python version: $(python --version 2>&1)"
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

start_boot_repair() {
  if [ ! -f "$BOOT_REPAIR_SCRIPT" ]; then
    log "[WARN] boot_repair.py not found: ${BOOT_REPAIR_SCRIPT}"
    return 0
  fi

  if pgrep -f "${BOOT_REPAIR_SCRIPT}" >/dev/null 2>&1; then
    log "[INFO] boot_repair.py already running; skip launching another one"
    return 0
  fi

  mkdir -p "$(dirname "$BOOT_REPAIR_LOG")"
  log "[INFO] launching boot_repair.py in background"
  log "[INFO] boot repair nohup log: ${BOOT_REPAIR_LOG}"

  nohup python "$BOOT_REPAIR_SCRIPT" \
    --log "$SERVICE_LOG" \
    >> "$BOOT_REPAIR_LOG" 2>&1 &
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
  activate_project_env
  core_gpu_assign_forge comfy

  if lsof -i :"${CF_LOCAL_PORT}" >/tmp/everspark_comfyui_port.log 2>&1; then
    log "[WARN] port ${CF_LOCAL_PORT} occupied:"
    cat /tmp/everspark_comfyui_port.log | tee -a "$START_LOG"

    if ! pgrep -f "main.py.*--port ${CF_LOCAL_PORT}" >/dev/null 2>&1; then
      log "[INFO] killing non-ComfyUI process on port ${CF_LOCAL_PORT}..."
      lsof -ti :"${CF_LOCAL_PORT}" | xargs -r kill
      sleep 2
    fi
  fi

  log "[1/3] starting ComfyUI..."
  log "[INFO] startup timeout: ${COMFY_START_TIMEOUT}s"
  log "[INFO] startup grace: ${COMFY_START_GRACE}s"

  if is_comfy_running; then
    log "[OK] ComfyUI already running on port ${CF_LOCAL_PORT}"
    start_boot_repair
    return 0
  fi

  [ -d "$COMFY_DIR" ] || die "COMFY_DIR not found: $COMFY_DIR"
  [ -f "$COMFY_DIR/main.py" ] || die "ComfyUI main.py not found: $COMFY_DIR/main.py"

  cd "$COMFY_DIR"
  mkdir -p "$(dirname "$SERVICE_LOG")"

  nohup python main.py --listen 0.0.0.0 --port "${CF_LOCAL_PORT}" \
    > "$SERVICE_LOG" 2>&1 &
  local comfy_pid=$!
  log "[INFO] ComfyUI process launched: pid=${comfy_pid}"

  for i in $(seq 1 "$COMFY_START_TIMEOUT"); do
    if curl -fsS "http://127.0.0.1:${CF_LOCAL_PORT}" >/dev/null 2>&1; then
      log "[OK] ComfyUI running on port ${CF_LOCAL_PORT}"
      start_boot_repair
      return 0
    fi

    if kill -0 "$comfy_pid" >/dev/null 2>&1; then
      sleep 1
      continue
    fi

    # During early bootstrap, the original child process can briefly be hard to
    # match by command line while imports and dependency installs are happening.
    # Give ComfyUI a short grace window before declaring startup failure.
    if [ "$i" -le "$COMFY_START_GRACE" ]; then
      if pgrep -f "main.py.*--port ${CF_LOCAL_PORT}" >/dev/null 2>&1 \
        || lsof -ti :"${CF_LOCAL_PORT}" >/dev/null 2>&1; then
        sleep 1
        continue
      fi

      log "[WARN] ComfyUI pid=${comfy_pid} not visible yet; waiting during grace window (${i}/${COMFY_START_GRACE})"
      sleep 1
      continue
    fi

    if pgrep -f "main.py.*--port ${CF_LOCAL_PORT}" >/dev/null 2>&1; then
      sleep 1
      continue
    fi

    log "[ERROR] ComfyUI exited"
    tail -n 120 "$SERVICE_LOG" | tee -a "$START_LOG" || true
    exit 1
  done

  log "[ERROR] ComfyUI healthcheck failed after ${COMFY_START_TIMEOUT}s"
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
  log "[INFO] boot repair log: ${BOOT_REPAIR_LOG}"

  if is_comfy_running; then
    log "[OK] ComfyUI HTTP healthcheck passed"
  else
    log "[WARN] ComfyUI HTTP healthcheck not ready"
  fi

  lsof -i :"${CF_LOCAL_PORT}" 2>&1 | tee -a "$START_LOG" || true
  pgrep -af "main.py|cloudflared|boot_repair.py|http.server" 2>&1 | tee -a "$START_LOG" || true
}

start_all() {
  log "== [EverSpark Forge] start all =="
  log "[INFO] hostname: ${CF_HOSTNAME}"
  log "[INFO] port: ${CF_LOCAL_PORT}"
  log "[INFO] ComfyUI log: ${SERVICE_LOG}"

  start_comfy
  start_tunnel

  log "[3/3] final check..."
  status_all

  log "========================================"
  log "[SUCCESS] EverSpark Forge is ONLINE 🚀"
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
