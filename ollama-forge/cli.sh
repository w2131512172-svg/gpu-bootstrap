#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

usage() {
  cat <<'EOF'
Ollama Forge commands

Usage:
  everspark ollama help
  everspark ollama restore
  everspark ollama service start
  everspark ollama service status
EOF
}

die() {
  echo "[ERROR] $*" >&2
  echo >&2
  usage >&2
  exit 1
}

run_script() {
  local script="$1"
  shift
  [ -f "$script" ] || die "script not found: $script"
  exec bash "$script" "$@"
}

show_status() {
  # shellcheck disable=SC1091
  source "${REPO_ROOT}/core/config/load_config.sh"

  local config_file="${CONFIG_FILE:-${SCRIPT_DIR}/config.env}"
  if [ -f "$config_file" ]; then
    core_load_config "$config_file"
  fi

  export OLLAMA_HOST="${OLLAMA_HOST:-127.0.0.1:${OLLAMA_PORT:-11434}}"

  if ! pgrep -x ollama >/dev/null 2>&1; then
    echo "[WARN] Ollama is not running."
    return 1
  fi

  echo "[OK] Ollama is running at http://${OLLAMA_HOST}"
  ollama list
}

command="${1:-help}"
if [ "$#" -gt 0 ]; then
  shift
fi

case "$command" in
  help|-h|--help)
    usage
    ;;
  restore)
    run_script "${SCRIPT_DIR}/restore_ollama_forge.sh" "$@"
    ;;
  service)
    subcommand="${1:-}"
    [ -n "$subcommand" ] || die "missing service subcommand"
    shift
    case "$subcommand" in
      start)
        run_script "${SCRIPT_DIR}/Ollama_start.sh" "$@"
        ;;
      status)
        show_status
        ;;
      *)
        die "unknown service subcommand: $subcommand"
        ;;
    esac
    ;;
  *)
    die "unknown command: $command"
    ;;
esac
