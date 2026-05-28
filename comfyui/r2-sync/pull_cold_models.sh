#!/usr/bin/env bash
set -euo pipefail

DRY_RUN=false
MODEL_TYPE=""
MODEL_NAMES=""

usage() {
  cat <<'EOF'
Usage:
  bash pull_cold_models.sh --type lora xxx,yyy,zzz
  bash pull_cold_models.sh --type checkpoint aaa,bbb
  bash pull_cold_models.sh -t lora xxx
  bash pull_cold_models.sh --dry-run --type lora xxx,yyy

Model name rule:
  Input names should NOT include .safetensors.
  Example: xxx -> xxx.safetensors

Supported types:
  lora | loras
  checkpoint | checkpoints
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
  *)
    echo "[ERROR] Missing or invalid --type. Use: lora or checkpoint"
    usage
    exit 1
    ;;
esac

if [ -z "$MODEL_NAMES" ]; then
  echo "[ERROR] Missing model names. Example: xxx,yyy,zzz"
  usage
  exit 1
fi

COMFYUI_ROOT="${COMFYUI_ROOT:-/root/ComfyUI}"
R2_ROOT_REMOTE="${R2_ROOT_REMOTE:-r2-assets:comfyui-assets}"
R2_COLD_REMOTE="${R2_COLD_REMOTE:-$R2_ROOT_REMOTE/models_cold}"
LOG_DIR="${AI_FORGE_LOG_DIR:-/root/ai_forge_logs}"
LOG_FILE="${LOG_FILE:-$LOG_DIR/r2_pull_cold_models.log}"

RCLONE_CONF_SRC="${RCLONE_CONF_SRC:-/root/rclone.conf}"
RCLONE_CONF_DST="${RCLONE_CONF_DST:-/root/.config/rclone/rclone.conf}"

REMOTE_DIR="$R2_COLD_REMOTE/$MODEL_BUCKET"
LOCAL_DIR="$COMFYUI_ROOT/models/$MODEL_BUCKET"

RCLONE_DRY_RUN_ARGS=()
if [ "$DRY_RUN" = true ]; then
  RCLONE_DRY_RUN_ARGS+=(--dry-run)
fi

mkdir -p "$LOG_DIR"
mkdir -p "$(dirname "$RCLONE_CONF_DST")"
mkdir -p "$LOCAL_DIR"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

die() {
  log "[ERROR] $*"
  exit 1
}

# ===== rclone config self-check =====
if [ -d "$RCLONE_CONF_DST" ]; then
  die "rclone config path is a directory: $RCLONE_CONF_DST"
fi

if [ ! -f "$RCLONE_CONF_DST" ]; then
  if [ -f "$RCLONE_CONF_SRC" ]; then
    cp "$RCLONE_CONF_SRC" "$RCLONE_CONF_DST"
    chmod 600 "$RCLONE_CONF_DST"
    log "[OK] rclone config copied: $RCLONE_CONF_SRC -> $RCLONE_CONF_DST"
  else
    die "rclone config not found: $RCLONE_CONF_DST or $RCLONE_CONF_SRC"
  fi
fi

log "============================================================"
log "[INFO] AI Forge cold model pull started"
log "[INFO] MODEL_BUCKET=$MODEL_BUCKET"
log "[INFO] REMOTE_DIR=$REMOTE_DIR"
log "[INFO] LOCAL_DIR=$LOCAL_DIR"
log "[INFO] LOG_FILE=$LOG_FILE"
if [ "$DRY_RUN" = true ]; then
  log "[INFO] DRY RUN MODE ENABLED"
fi
log "============================================================"

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
    log "[SKIP] already exists locally: $local_file"
    return 0
  fi

  if ! rclone lsf "$remote_file" >/dev/null 2>&1; then
    log "[WARN] remote model not found: $remote_file"
    return 0
  fi

  log "[COPY] $remote_file -> $local_file"
  rclone copyto "$remote_file" "$local_file" \
    --progress \
    --log-file "$LOG_FILE" \
    --log-level INFO \
    "${RCLONE_DRY_RUN_ARGS[@]}"

  log "[OK] pulled: $filename"
}

IFS=',' read -ra MODEL_ARRAY <<< "$MODEL_NAMES"

for name in "${MODEL_ARRAY[@]}"; do
  pull_one_model "$name"
done

log "============================================================"
log "[OK] AI Forge cold model pull completed"
log "[INFO] Log: $LOG_FILE"
log "============================================================"
