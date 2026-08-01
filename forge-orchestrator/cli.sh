#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
usage() {
  cat <<'EOF'
Forge Orchestrator commands

Usage:
  everspark orchestrator start
  everspark orchestrator console
EOF
}
case "${1:-help}" in
  start|core) exec bash "${SCRIPT_DIR}/scripts/start_core.sh" ;;
  console|cli) exec bash "${SCRIPT_DIR}/scripts/start_cli.sh" ;;
  help|-h|--help) usage ;;
  *) usage >&2; echo "[ERROR] unknown Orchestrator command: $1" >&2; exit 1 ;;
esac
