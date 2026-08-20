#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck disable=SC1091
source "${REPO_ROOT}/core/logging/log.sh"
# shellcheck disable=SC1091
source "${REPO_ROOT}/core/hardware/gpu_assignment.sh"

if [ -f /root/.env ]; then
  set -a
  # shellcheck disable=SC1091
  source /root/.env
  set +a
fi

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

core_log_init comfyui.service "$START_LOG"

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
    core_info environment.provided "Service environment was provided" "environment=$ENV_NAME"
    return 0
  fi

  local selected_profile="$TORCH_PROFILE"

  if [ "$selected_profile" = "auto" ]; then
    if [ -x "${SCRIPT_DIR}/detect_torch_profile.sh" ] || [ -f "${SCRIPT_DIR}/detect_torch_profile.sh" ]; then
      selected_profile="$(bash "${SCRIPT_DIR}/detect_torch_profile.sh" | tail -n 1 | tr -d '[:space:]')"
      core_info torch.profile.detected "Torch profile detected for service startup" \
        "profile=$selected_profile"
    else
      selected_profile="cu121"
      core_warn torch.detector.missing "Torch profile detector was not found; using fallback" \
        "profile=$selected_profile"
    fi
  else
    core_info torch.profile.provided "Torch profile was provided for service startup" \
      "profile=$selected_profile"
  fi

  case "$selected_profile" in
    cu128)
      ENV_NAME="torch-cu128"
      ;;
    cu121)
      ENV_NAME="torch251-cu121"
      ;;
    *)
      core_die torch.profile.unsupported "Unsupported Torch profile for service startup" \
        "profile=$selected_profile"
      return 1
      ;;
  esac

  TORCH_PROFILE="$selected_profile"
  export TORCH_PROFILE ENV_NAME
  core_ok environment.selected "Service environment selected" \
    "profile=$TORCH_PROFILE" "environment=$ENV_NAME"
}

activate_project_env() {
  resolve_env_name

  local conda_sh="${MINICONDA_DIR}/etc/profile.d/conda.sh"
  if [ ! -f "$conda_sh" ]; then
    core_die conda.init.missing "Conda initialization script was not found" "path=$conda_sh"
    return 1
  fi

  # shellcheck disable=SC1090
  source "$conda_sh"
  conda activate "$ENV_NAME"

  if ! command -v python >/dev/null 2>&1; then
    core_die python.missing "Python was not found after activating the service environment"
    return 1
  fi

  core_ok environment.active "Service environment activated" \
    "environment=$ENV_NAME" "python=$(command -v python)" \
    "python_version=$(python --version 2>&1)"
}

kill_wrong_services() {
  core_info service.cleanup "Cleaning incompatible HTTP test services"
  pkill -f "python -m http.server" 2>/dev/null || true
  pkill -f "http.server" 2>/dev/null || true
}

is_comfy_running() {
  curl -fsS "http://127.0.0.1:${CF_LOCAL_PORT}" >/dev/null 2>&1 \
    && pgrep -f "main.py.*--port ${CF_LOCAL_PORT}" >/dev/null 2>&1
}

start_boot_repair() {
  if [ ! -f "$BOOT_REPAIR_SCRIPT" ]; then
    core_warn boot_repair.missing "Boot repair script was not found" "path=$BOOT_REPAIR_SCRIPT"
    return 0
  fi

  if pgrep -f "${BOOT_REPAIR_SCRIPT}" >/dev/null 2>&1; then
    core_info boot_repair.running "Boot repair is already running"
    return 0
  fi

  mkdir -p "$(dirname "$BOOT_REPAIR_LOG")"
  nohup python "$BOOT_REPAIR_SCRIPT" \
    --log "$SERVICE_LOG" \
    >> "$BOOT_REPAIR_LOG" 2>&1 &

  core_ok boot_repair.started "Boot repair started in the background" \
    "pid=$!" "log_file=$BOOT_REPAIR_LOG"
}

stop_comfy() {
  core_info service.stop.requested "Stopping ComfyUI" "port=$CF_LOCAL_PORT"

  if pgrep -f "main.py.*--port ${CF_LOCAL_PORT}" >/dev/null 2>&1; then
    pkill -f "main.py.*--port ${CF_LOCAL_PORT}" 2>/dev/null || true
    sleep 2
  fi

  if lsof -ti :"$CF_LOCAL_PORT" >/dev/null 2>&1; then
    core_warn service.port.occupied "Port is still occupied; stopping the port owner" \
      "port=$CF_LOCAL_PORT"
    lsof -ti :"$CF_LOCAL_PORT" | xargs -r kill 2>/dev/null || true
    sleep 2
  fi

  if pgrep -f "main.py.*--port ${CF_LOCAL_PORT}" >/dev/null 2>&1; then
    core_warn service.stop.escalated "ComfyUI is still running; forcing shutdown"
    pkill -9 -f "main.py.*--port ${CF_LOCAL_PORT}" 2>/dev/null || true
    sleep 1
  fi

  if pgrep -f "main.py.*--port ${CF_LOCAL_PORT}" >/dev/null 2>&1; then
    core_die service.stop.failed "Failed to stop ComfyUI" "port=$CF_LOCAL_PORT"
    return 1
  fi

  core_ok service.stopped "ComfyUI stopped" "port=$CF_LOCAL_PORT"
}

report_port_owner() {
  local report_file
  report_file="$(mktemp)"
  if lsof -i :"$CF_LOCAL_PORT" >"$report_file" 2>&1; then
    core_warn service.port.occupied "ComfyUI port is occupied" "port=$CF_LOCAL_PORT"
    sed -n '1,40p' "$report_file"
    rm -f "$report_file"
    return 0
  fi
  rm -f "$report_file"
  return 1
}

start_comfy() {
  kill_wrong_services
  activate_project_env
  core_gpu_assign_forge comfy

  if report_port_owner; then
    if ! pgrep -f "main.py.*--port ${CF_LOCAL_PORT}" >/dev/null 2>&1; then
      core_info service.port.release "Stopping a non-ComfyUI port owner" "port=$CF_LOCAL_PORT"
      lsof -ti :"$CF_LOCAL_PORT" | xargs -r kill
      sleep 2
    fi
  fi

  core_info service.start.requested "Starting ComfyUI" \
    "port=$CF_LOCAL_PORT" "timeout_seconds=$COMFY_START_TIMEOUT" \
    "grace_seconds=$COMFY_START_GRACE"

  if is_comfy_running; then
    core_ok service.already_running "ComfyUI is already running" "port=$CF_LOCAL_PORT"
    start_boot_repair
    return 0
  fi

  if [ ! -d "$COMFY_DIR" ]; then
    core_die service.directory.missing "ComfyUI directory was not found" "path=$COMFY_DIR"
    return 1
  fi
  if [ ! -f "$COMFY_DIR/main.py" ]; then
    core_die service.entrypoint.missing "ComfyUI entrypoint was not found" "path=$COMFY_DIR/main.py"
    return 1
  fi

  cd "$COMFY_DIR"
  mkdir -p "$(dirname "$SERVICE_LOG")"

  nohup python main.py --listen 0.0.0.0 --port "$CF_LOCAL_PORT" \
    > "$SERVICE_LOG" 2>&1 &
  local comfy_pid=$!
  core_info service.process.started "ComfyUI process launched" \
    "pid=$comfy_pid" "log_file=$SERVICE_LOG"

  local i
  for i in $(seq 1 "$COMFY_START_TIMEOUT"); do
    if curl -fsS "http://127.0.0.1:${CF_LOCAL_PORT}" >/dev/null 2>&1; then
      core_ok service.ready "ComfyUI health check passed" \
        "port=$CF_LOCAL_PORT" "pid=$comfy_pid"
      start_boot_repair
      return 0
    fi

    if kill -0 "$comfy_pid" >/dev/null 2>&1; then
      sleep 1
      continue
    fi

    if [ "$i" -le "$COMFY_START_GRACE" ]; then
      if pgrep -f "main.py.*--port ${CF_LOCAL_PORT}" >/dev/null 2>&1 \
        || lsof -ti :"$CF_LOCAL_PORT" >/dev/null 2>&1; then
        sleep 1
        continue
      fi

      core_warn service.process.pending "ComfyUI process is not visible during the grace window" \
        "pid=$comfy_pid" "attempt=$i" "grace_seconds=$COMFY_START_GRACE"
      sleep 1
      continue
    fi

    if pgrep -f "main.py.*--port ${CF_LOCAL_PORT}" >/dev/null 2>&1; then
      sleep 1
      continue
    fi

    core_error service.exited "ComfyUI exited before becoming ready" \
      "pid=$comfy_pid" "log_file=$SERVICE_LOG"
    tail -n 120 "$SERVICE_LOG" >&2 || true
    return 1
  done

  core_error service.timeout "ComfyUI health check timed out" \
    "timeout_seconds=$COMFY_START_TIMEOUT" "log_file=$SERVICE_LOG"
  tail -n 120 "$SERVICE_LOG" >&2 || true
  return 1
}

start_tunnel() {
  bash "${SCRIPT_DIR}/tunnel/start_tunnel.sh"
}

status_all() {
  core_info service.status "Reporting ComfyUI Forge status" \
    "hostname=$CF_HOSTNAME" "port=$CF_LOCAL_PORT" \
    "service_log=$SERVICE_LOG" "lifecycle_log=$START_LOG" \
    "boot_repair_log=$BOOT_REPAIR_LOG"

  if is_comfy_running; then
    core_ok service.health.ready "ComfyUI HTTP health check passed" "port=$CF_LOCAL_PORT"
  else
    core_warn service.health.pending "ComfyUI HTTP health check is not ready" "port=$CF_LOCAL_PORT"
  fi

  lsof -i :"$CF_LOCAL_PORT" 2>&1 || true
  pgrep -af "main.py|cloudflared|boot_repair.py|http.server" 2>&1 || true
}

start_all() {
  core_info stack.start "Starting ComfyUI Forge services" \
    "hostname=$CF_HOSTNAME" "port=$CF_LOCAL_PORT"

  core_run_step comfyui.start start_comfy
  core_run_step tunnel.start start_tunnel
  status_all

  core_ok stack.ready "EverSpark Forge is online" "url=https://${CF_HOSTNAME}"
}

cmd="${1:-start}"

case "$cmd" in
  start)
    start_all
    ;;
  stop)
    core_run_step comfyui.stop stop_comfy
    ;;
  restart)
    core_run_step comfyui.stop stop_comfy
    core_run_step comfyui.start start_comfy
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
    core_die command.unknown "Unknown start_all command" "command=$cmd"
    ;;
esac
