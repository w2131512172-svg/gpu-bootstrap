#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck disable=SC1091
source "${REPO_ROOT}/core/logging/log.sh"
# shellcheck disable=SC1091
source "${REPO_ROOT}/core/config/load_config.sh"
# shellcheck disable=SC1091
source "${REPO_ROOT}/core/storage/rclone.sh"

prepare_private_env_file() {
  if [ ! -f /root/.env ] && [ -f /root/env.txt ]; then
    mv /root/env.txt /root/.env
  fi

  if [ -f /root/.env ]; then
    chmod 600 /root/.env
    set -a
    # shellcheck disable=SC1091
    source /root/.env
    set +a
  fi
}

# Load operator configuration before resolving logger paths and runtime defaults.
prepare_private_env_file

LOG_DIR="${EVERSPARK_LOG_DIR:-/root/everspark_logs}"
FORGE_LOG="${FORGE_LOG:-${LOG_DIR}/recovery.log}"

TORCH_PROFILE="${TORCH_PROFILE:-auto}"
USER_ENV_NAME="${ENV_NAME:-}"
ENV_NAME="${ENV_NAME:-}"
MINICONDA_DIR="${MINICONDA_DIR:-/root/miniconda3}"

core_log_init comfyui.recovery "$FORGE_LOG"

prepare_private_configs() {
  core_info config.prepare "Preparing private configuration"

  if [ -f /root/.env ]; then
    core_ok config.env.ready "Private environment file is ready" "path=/root/.env"
  else
    core_warn config.env.missing "Private environment file was not found; defaults will be used"
  fi

  local rclone_src="${RCLONE_CONF_SRC:-/root/rclone.conf}"
  local rclone_dst="${RCLONE_CONF_DST:-$(core_rclone_config_path)}"

  if [ -f "$rclone_src" ] || [ -f "$rclone_dst" ]; then
    core_rclone_ensure_config "$rclone_src" "$rclone_dst"
    [ ! -f "$rclone_src" ] || chmod 600 "$rclone_src"
  else
    core_warn config.rclone.missing "rclone configuration is not available yet" \
      "source=$rclone_src" "runtime=$rclone_dst"
  fi

  core_ok config.ready "Private configuration preparation completed"
}

install_everspark_cli() {
  local installer="${REPO_ROOT}/core/cli/install.sh"
  if [ ! -f "$installer" ]; then
    core_die cli.installer.missing "EverSpark CLI installer was not found" "path=$installer"
    return 1
  fi

  bash "$installer"
  core_ok cli.ready "EverSpark Forge CLI is available" "command=everspark"
}

detect_torch_profile() {
  if [ "$TORCH_PROFILE" != "auto" ]; then
    core_info torch.profile.provided "Torch profile was provided" "profile=$TORCH_PROFILE"
  else
    local detector="$SCRIPT_DIR/detect_torch_profile.sh"
    if [ ! -f "$detector" ]; then
      core_die torch.detector.missing "Torch profile detector was not found" "path=$detector"
      return 1
    fi

    TORCH_PROFILE="$(bash "$detector")"
    core_info torch.profile.detected "Torch profile detected" "profile=$TORCH_PROFILE"
  fi

  case "$TORCH_PROFILE" in
    cu128)
      ENV_NAME="${USER_ENV_NAME:-torch-cu128}"
      ;;
    cu121)
      ENV_NAME="${USER_ENV_NAME:-torch251-cu121}"
      ;;
    *)
      core_die torch.profile.unsupported "Unsupported Torch profile" "profile=$TORCH_PROFILE"
      return 1
      ;;
  esac

  export TORCH_PROFILE ENV_NAME
  core_ok torch.environment.selected "Project environment selected" \
    "profile=$TORCH_PROFILE" "environment=$ENV_NAME"
}

activate_project_env() {
  local conda_sh="${MINICONDA_DIR}/etc/profile.d/conda.sh"
  if [ ! -f "$conda_sh" ]; then
    core_die conda.init.missing "Conda initialization script was not found" "path=$conda_sh"
    return 1
  fi

  # shellcheck disable=SC1090
  source "$conda_sh"
  conda activate "$ENV_NAME"

  if ! command -v python >/dev/null 2>&1; then
    core_die python.missing "Python was not found after activating the project environment"
    return 1
  fi

  core_ok conda.environment.active "Project environment activated" \
    "environment=$ENV_NAME" "python=$(command -v python)" \
    "python_version=$(python --version 2>&1)"
}

core_info recovery.start "EverSpark Forge recovery started" \
  "script_dir=$SCRIPT_DIR" "log_file=$FORGE_LOG"

core_run_step config.prepare prepare_private_configs
core_run_step cli.install install_everspark_cli
core_run_step torch.detect detect_torch_profile

case "$TORCH_PROFILE" in
  cu128)
    BOOTSTRAP_SCRIPT="$SCRIPT_DIR/bootstrap-cu128.sh"
    ;;
  cu121)
    BOOTSTRAP_SCRIPT="$SCRIPT_DIR/bootstrap-cu121.sh"
    ;;
esac

core_run_step environment.bootstrap bash "$BOOTSTRAP_SCRIPT"
core_run_step environment.activate activate_project_env
core_run_step comfyui.restore bash "$SCRIPT_DIR/restore_comfyui_core.sh"
core_run_step r2.check bash "$SCRIPT_DIR/r2-sync/check_r2.sh"
core_run_step r2.pull bash "$SCRIPT_DIR/r2-sync/pull_from_r2.sh"
core_run_step dependencies.check bash "$SCRIPT_DIR/deps/check_deps.sh"
core_run_step dependencies.install python "$SCRIPT_DIR/deps/auto_deps.py"
core_run_optional_step sam3.repair bash "$SCRIPT_DIR/deps/fix_sam3_env.sh"
core_run_step services.start bash "$SCRIPT_DIR/start_all.sh" start

core_ok recovery.complete "EverSpark Forge recovery completed" \
  "profile=$TORCH_PROFILE" "environment=$ENV_NAME"
