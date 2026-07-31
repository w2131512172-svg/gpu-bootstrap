#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck disable=SC1091
source "${REPO_ROOT}/core/logging/log.sh"
# shellcheck disable=SC1091
source "${REPO_ROOT}/core/config/load_config.sh"

CONFIG_FILE="${CONFIG_FILE:-/root/.env}"

load_environment_config() {
  if [ -f "$CONFIG_FILE" ]; then
    core_load_config "$CONFIG_FILE"
  fi

  MINICONDA_DIR="${MINICONDA_DIR:-/root/miniconda3}"
}

remove_legacy_auto_activate() {
  local bashrc="${HOME}/.bashrc"
  local marker="# Auto-activate AI Forge project env"

  if [ ! -f "$bashrc" ] || ! grep -qF "$marker" "$bashrc"; then
    core_ok "ComfyUI shell auto-activation is disabled."
    return 0
  fi

  sed -i '/^# Auto-activate AI Forge project env$/,/^fi$/d' "$bashrc"
  core_ok "Removed legacy ComfyUI auto-activation from: $bashrc"
}

prepare_conda_shell() {
  local conda_bin="${MINICONDA_DIR}/bin/conda"

  if [ ! -x "$conda_bin" ]; then
    core_die "Conda not found: $conda_bin"
    return 1
  fi

  "$conda_bin" init bash >/dev/null
  "$conda_bin" config --set auto_activate_base false
  remove_legacy_auto_activate
}

resolve_environment_name() {
  if [ -n "${ENV_NAME:-}" ]; then
    printf '%s\n' "$ENV_NAME"
    return 0
  fi

  local profile="${TORCH_PROFILE:-auto}"
  if [ "$profile" = "auto" ]; then
    profile="$(bash "${SCRIPT_DIR}/detect_torch_profile.sh")"
  fi

  case "$profile" in
    cu121)
      printf '%s\n' "torch251-cu121"
      ;;
    cu128)
      printf '%s\n' "torch-cu128"
      ;;
    *)
      core_die "Unsupported ComfyUI torch profile: $profile"
      return 1
      ;;
  esac
}

enter_shell() {
  local env_name conda_sh shell_bin

  env_name="$(resolve_environment_name)"
  conda_sh="${MINICONDA_DIR}/etc/profile.d/conda.sh"
  shell_bin="${SHELL:-/bin/bash}"

  if [ ! -f "$conda_sh" ]; then
    core_die "Conda shell integration not found: $conda_sh"
    return 1
  fi

  # shellcheck disable=SC1090
  source "$conda_sh"

  if ! conda env list | awk '{print $1}' | grep -qx "$env_name"; then
    core_die "ComfyUI Conda environment not found: $env_name"
    return 1
  fi

  conda activate "$env_name"
  core_ok "Entering ComfyUI Forge environment: $env_name"
  core_info "Python: $(command -v python)"
  core_info "Exit with: exit"

  exec "$shell_bin" -i
}

usage() {
  cat <<'EOF'
Usage:
  bash comfyui/environment.sh cleanup
  bash comfyui/environment.sh shell
EOF
}

main() {
  load_environment_config
  prepare_conda_shell

  case "${1:-shell}" in
    cleanup)
      ;;
    shell|enter|activate)
      enter_shell
      ;;
    help|-h|--help)
      usage
      ;;
    *)
      usage >&2
      core_die "Unknown environment command: $1"
      ;;
  esac
}

main "$@"
