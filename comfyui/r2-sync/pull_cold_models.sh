#!/usr/bin/env bash
set -euo pipefail

R2_SYNC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_REPO_ROOT="$(cd "${R2_SYNC_DIR}/../.." && pwd)"
# shellcheck disable=SC1091
source "${CORE_REPO_ROOT}/core/storage/rclone.sh"

LOG_DIR="${EVERSPARK_LOG_DIR:-/root/everspark_logs}"
LOG_FILE="${LOG_FILE:-${LOG_DIR}/r2.log}"
RCLONE_LOG="${RCLONE_LOG:-${LOG_DIR}/rclone.log}"
core_log_init r2.pull.cold "$LOG_FILE"

DRY_RUN=false
MODEL_TYPE=""
MODEL_NAMES=""

usage() {
  cat <<'EOF'
Usage:
  bash pull_cold_models.sh --type lora xxx,yyy,zzz
  bash pull_cold_models.sh --type checkpoint aaa,bbb
  bash pull_cold_models.sh --type diffusion xxx,yyy
  bash pull_cold_models.sh -t lora xxx
  bash pull_cold_models.sh --dry-run --type diffusion xxx,yyy

Model name rule:
  Input names should NOT include .safetensors.
  Example: xxx -> xxx.safetensors

Supported types:
  lora | loras
  checkpoint | checkpoints
  diffusion | diffusion_model | diffusion_models
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --type|-t)
      MODEL_TYPE="${2:-}"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      if [ -z "$MODEL_NAMES" ]; then
        MODEL_NAMES="$1"
      else
        MODEL_NAMES="$MODEL_NAMES,$1"
      fi
      shift
      ;;
  esac
done

case "$MODEL_TYPE" in
  lora|loras)
    MODEL_BUCKET="loras"
    ;;
  checkpoint|checkpoints)
    MODEL_BUCKET="checkpoints"
    ;;
  diffusion|diffusion_model|diffusion_models)
    MODEL_BUCKET="diffusion_models"
    ;;
  *)
    core_error r2.arguments "Missing or invalid --type. Use: lora, checkpoint, or diffusion"
    usage
    exit 1
    ;;
esac

if [ -z "$MODEL_NAMES" ]; then
  core_error r2.arguments "Missing model names. Example: xxx,yyy,zzz"
  usage
  exit 1
fi

COMFYUI_ROOT="${COMFYUI_ROOT:-/root/ComfyUI}"
R2_ROOT_REMOTE="${R2_ROOT_REMOTE:-r2-assets:comfyui-assets}"
R2_COLD_REMOTE="${R2_COLD_REMOTE:-$R2_ROOT_REMOTE/models_cold}"

RCLONE_CONF_SRC="${RCLONE_CONF_SRC:-/root/rclone.conf}"
RCLONE_CONF_DST="${RCLONE_CONF_DST:-$(core_rclone_config_path)}"

REMOTE_DIR="$R2_COLD_REMOTE/$MODEL_BUCKET"
LOCAL_DIR="$COMFYUI_ROOT/models/$MODEL_BUCKET"

RCLONE_DRY_RUN_ARGS=()
if [ "$DRY_RUN" = true ]; then
  RCLONE_DRY_RUN_ARGS+=(--dry-run)
fi

mkdir -p "$LOCAL_DIR"


# ===== Core rclone connection =====
core_rclone_ensure_config "$RCLONE_CONF_SRC" "$RCLONE_CONF_DST"
core_info r2.status "EverSpark Forge cold model pull started"
core_info r2.status "MODEL_BUCKET=$MODEL_BUCKET"
core_info r2.status "REMOTE_DIR=$REMOTE_DIR"
core_info r2.status "LOCAL_DIR=$LOCAL_DIR"
core_info r2.status "LOG_FILE=$LOG_FILE"
if [ "$DRY_RUN" = true ]; then
  core_info r2.status "DRY RUN MODE ENABLED"
fi

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

normalize_model_name() {
  local value="$1"
  value="$(trim "$value")"
  value="${value%.safetensors}"
  printf '%s' "$value"
}

pull_one_model() {
  local raw_name="$1"
  local model_name
  local filename
  local remote_file
  local local_file

  model_name="$(normalize_model_name "$raw_name")"

  if [ -z "$model_name" ]; then
    return 0
  fi

  filename="$model_name.safetensors"
  remote_file="$REMOTE_DIR/$filename"
  local_file="$LOCAL_DIR/$filename"

  if [ -f "$local_file" ]; then
    core_info r2.progress "[SKIP] already exists locally: $local_file"
    return 0
  fi

  if ! rclone lsf "$remote_file" >/dev/null 2>&1; then
    core_warn r2.status "remote model not found: $remote_file"
    return 0
  fi

  core_info r2.progress "[COPY] $remote_file -> $local_file"
  core_rclone_copyto "$remote_file" "$local_file" \
    --progress \
    --log-file "$RCLONE_LOG" \
    --log-level INFO \
    "${RCLONE_DRY_RUN_ARGS[@]}"

  core_ok r2.status "pulled: $filename"
}

IFS=',' read -ra MODEL_ARRAY <<< "$MODEL_NAMES"

for name in "${MODEL_ARRAY[@]}"; do
  pull_one_model "$name"
done
core_ok r2.status "EverSpark Forge cold model pull completed"
core_info r2.status "Log: $LOG_FILE"

