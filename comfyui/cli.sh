#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
R2_DIR="${SCRIPT_DIR}/r2-sync"

usage() {
  cat <<'EOF'
ComfyUI Forge commands

Usage:
  everspark comfy help
  everspark comfy restore
  everspark comfy shell

  everspark comfy storage check
  everspark comfy storage pull [--dry-run]
  everspark comfy storage push [--dry-run]
  everspark comfy storage push-clean [--dry-run]
  everspark comfy storage clean [--dry-run]

  everspark comfy models pull [--dry-run] <manifest.json>
  everspark comfy models pull-manual [--dry-run] <type> <name1,name2>

  everspark comfy service start
  everspark comfy service stop
  everspark comfy service restart
  everspark comfy service status
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

command="${1:-help}"
if [ "$#" -gt 0 ]; then
  shift
fi

case "$command" in
  help|-h|--help)
    usage
    ;;
  restore)
    run_script "${SCRIPT_DIR}/comfy_start.sh" "$@"
    ;;
  shell|env)
    run_script "${SCRIPT_DIR}/environment.sh" shell "$@"
    ;;
  storage)
    subcommand="${1:-}"
    [ -n "$subcommand" ] || die "missing storage subcommand"
    shift
    case "$subcommand" in
      check|doctor)
        run_script "${R2_DIR}/check_r2.sh" "$@"
        ;;
      pull)
        run_script "${R2_DIR}/pull_from_r2.sh" "$@"
        ;;
      push)
        run_script "${R2_DIR}/push_incremental.sh" "$@"
        ;;
      push-clean)
        run_script "${R2_DIR}/push_clean_incremental.sh" "$@"
        ;;
      clean)
        run_script "${R2_DIR}/clean_local_junk.sh" "$@"
        ;;
      *)
        die "unknown storage subcommand: $subcommand"
        ;;
    esac
    ;;
  models)
    subcommand="${1:-}"
    [ -n "$subcommand" ] || die "missing models subcommand"
    shift
    case "$subcommand" in
      pull)
        dry_run=false
        if [ "${1:-}" = "--dry-run" ]; then
          dry_run=true
          shift
        fi
        manifest="${1:-}"
        [ -n "$manifest" ] || die "missing manifest file"
        shift
        if [ "$dry_run" = true ]; then
          run_script "${R2_DIR}/pull_cold_models_manifest_dual_mode.sh" --dry-run --manifest "$manifest" "$@"
        else
          run_script "${R2_DIR}/pull_cold_models_manifest_dual_mode.sh" --manifest "$manifest" "$@"
        fi
        ;;
      pull-manual)
        dry_run=false
        if [ "${1:-}" = "--dry-run" ]; then
          dry_run=true
          shift
        fi
        model_type="${1:-}"
        model_names="${2:-}"
        [ -n "$model_type" ] || die "missing model type"
        [ -n "$model_names" ] || die "missing model names"
        shift 2
        if [ "$dry_run" = true ]; then
          run_script "${R2_DIR}/pull_cold_models_manifest_dual_mode.sh" --dry-run --type "$model_type" "$model_names" "$@"
        else
          run_script "${R2_DIR}/pull_cold_models_manifest_dual_mode.sh" --type "$model_type" "$model_names" "$@"
        fi
        ;;
      *)
        die "unknown models subcommand: $subcommand"
        ;;
    esac
    ;;
  service)
    subcommand="${1:-}"
    [ -n "$subcommand" ] || die "missing service subcommand"
    shift
    case "$subcommand" in
      start|stop|restart|status)
        run_script "${SCRIPT_DIR}/start_all.sh" "$subcommand" "$@"
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
