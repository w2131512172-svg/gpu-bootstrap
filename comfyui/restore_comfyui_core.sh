#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck disable=SC1091
source "${REPO_ROOT}/core/logging/log.sh"

COMFYUI_ROOT="${COMFYUI_ROOT:-/root/ComfyUI}"
COMFYUI_REPO="${COMFYUI_REPO:-https://github.com/Comfy-Org/ComfyUI.git}"
COMFYUI_VERSION="${COMFYUI_VERSION:-v0.20.1}"

LOG_DIR="${EVERSPARK_LOG_DIR:-/root/everspark_logs}"
LOG_FILE="${COMFYUI_CORE_LOG:-${CORE_LOG_FILE:-${LOG_DIR}/recovery.log}}"
CORE_INFO_FILE="${COMFYUI_CORE_INFO_FILE:-/root/comfyui_core_info.txt}"

core_log_init comfyui.restore "$LOG_FILE"

core_info restore.start "Restoring ComfyUI core" \
  "root=$COMFYUI_ROOT" "repository=$COMFYUI_REPO" "version=$COMFYUI_VERSION"

if ! command -v git >/dev/null 2>&1; then
  core_die git.missing "Git command was not found"
  exit 1
fi

if [ -d "$COMFYUI_ROOT/.git" ]; then
  core_ok restore.repository.ready "Existing ComfyUI repository found" "root=$COMFYUI_ROOT"
elif [ -e "$COMFYUI_ROOT" ]; then
  core_die restore.path.invalid "ComfyUI root exists but is not a Git repository" \
    "root=$COMFYUI_ROOT"
  exit 1
else
  core_info restore.clone "Cloning ComfyUI core" "repository=$COMFYUI_REPO"
  git clone "$COMFYUI_REPO" "$COMFYUI_ROOT"
fi

cd "$COMFYUI_ROOT"

core_info restore.fetch "Fetching ComfyUI tags"
git fetch --tags

core_info restore.checkout "Checking out ComfyUI version" "version=$COMFYUI_VERSION"
git checkout "$COMFYUI_VERSION"

if [ ! -f "$COMFYUI_ROOT/main.py" ]; then
  core_die restore.entrypoint.missing "ComfyUI entrypoint is missing after checkout" \
    "path=$COMFYUI_ROOT/main.py"
  exit 1
fi

CURRENT_COMMIT="$(git rev-parse HEAD)"
CURRENT_REF="$(git describe --tags --always 2>/dev/null || git rev-parse --short HEAD)"

cat > "$CORE_INFO_FILE" <<EOF
EVERSPARK_COMFYUI_CORE_INFO
CREATED_AT=$(date '+%Y-%m-%d %H:%M:%S')

COMFYUI_ROOT=$COMFYUI_ROOT
COMFYUI_REPO=$COMFYUI_REPO
COMFYUI_VERSION=$COMFYUI_VERSION
CURRENT_REF=$CURRENT_REF
CURRENT_COMMIT=$CURRENT_COMMIT
EOF

core_ok restore.complete "ComfyUI core is ready" \
  "ref=$CURRENT_REF" "commit=$CURRENT_COMMIT" "info_file=$CORE_INFO_FILE"
