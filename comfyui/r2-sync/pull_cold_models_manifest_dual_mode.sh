#!/usr/bin/env bash
set -euo pipefail

R2_SYNC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_REPO_ROOT="$(cd "${R2_SYNC_DIR}/../.." && pwd)"
# shellcheck disable=SC1091
source "${CORE_REPO_ROOT}/core/storage/rclone.sh"

DRY_RUN=false
MODEL_TYPE=""
MODEL_NAMES=""
MANIFEST_FILE=""

usage() {
  cat <<'USAGE_EOF'
Usage:
  # Manual mode
  bash pull_cold_models.sh --type lora xxx,yyy,zzz
  bash pull_cold_models.sh --type checkpoint aaa,bbb
  bash pull_cold_models.sh --type diffusion xxx,yyy
  bash pull_cold_models.sh -t lora xxx
  bash pull_cold_models.sh --dry-run --type diffusion xxx,yyy

  # Manifest mode
  bash pull_cold_models.sh --manifest pod_lora_pull_manifest.json
  bash pull_cold_models.sh --dry-run --manifest pod_lora_pull_manifest.json

Manual model name rule:
  Input names should NOT include .safetensors.
  Example: xxx -> xxx.safetensors

Manifest JSON format:
  {
    "type": "lora",
    "items": ["xxx", "yyy", "zzz"]
  }

  or:

  {
    "model_type": "lora",
    "items": [
      {"name": "xxx"},
      {"name": "yyy", "r2_filename": "yyy.safetensors"}
    ]
  }

Supported types:
  lora | loras
  checkpoint | checkpoints
  diffusion | diffusion_model | diffusion_models

Notes:
  - Manual mode and manifest mode share the same pulling logic.
  - Manifest names should normally match local md file names without .md.
  - xxx.md -> xxx.safetensors
  - Remote and local model filename matching is case-insensitive.
USAGE_EOF
}

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

normalize_model_type() {
  local value="$1"

  case "$value" in
    lora|loras)
      printf '%s' "loras"
      ;;
    checkpoint|checkpoints)
      printf '%s' "checkpoints"
      ;;
    diffusion|diffusion_model|diffusion_models)
      printf '%s' "diffusion_models"
      ;;
    *)
      return 1
      ;;
  esac
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
    --manifest|-m)
      MANIFEST_FILE="${2:-}"
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

COMFYUI_ROOT="${COMFYUI_ROOT:-/root/ComfyUI}"
R2_ROOT_REMOTE="${R2_ROOT_REMOTE:-r2-assets:comfyui-assets}"
R2_COLD_REMOTE="${R2_COLD_REMOTE:-$R2_ROOT_REMOTE/models_cold}"
LOG_DIR="${AI_FORGE_LOG_DIR:-/root/ai_forge_logs}"
LOG_FILE="${LOG_FILE:-$LOG_DIR/r2_pull_cold_models.log}"

RCLONE_CONF_SRC="${RCLONE_CONF_SRC:-/root/rclone.conf}"
RCLONE_CONF_DST="${RCLONE_CONF_DST:-$(core_rclone_config_path)}"

mkdir -p "$LOG_DIR"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

die() {
  log "[ERROR] $*"
  exit 1
}

require_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    die "jq is required for --manifest mode. Install jq or use manual mode."
  fi
}

load_manifest() {
  local manifest="$1"
  local manifest_type
  local manifest_names

  if [ ! -f "$manifest" ]; then
    die "manifest file not found: $manifest"
  fi

  require_jq

  manifest_type="$(jq -r '.type // .model_type // empty' "$manifest")"
  if [ -z "$manifest_type" ]; then
    die "manifest missing type/model_type: $manifest"
  fi

  MODEL_TYPE="$manifest_type"

  # Supports two item formats:
  # 1) ["xxx", "yyy"]
  # 2) [{"name":"xxx"}, {"r2_filename":"yyy.safetensors"}]
  manifest_names="$(jq -r '
    .items // [] |
    map(
      if type == "string" then
        .
      elif type == "object" then
        (.name // .model_name // .r2_name // .r2_filename // empty)
      else
        empty
      end
    ) |
    map(select(. != null and . != "")) |
    join(",")
  ' "$manifest")"

  if [ -z "$manifest_names" ]; then
    die "manifest contains no model names: $manifest"
  fi

  MODEL_NAMES="$manifest_names"
}

if [ -n "$MANIFEST_FILE" ]; then
  if [ -n "$MODEL_NAMES" ] || [ -n "$MODEL_TYPE" ]; then
    die "--manifest mode should not be mixed with manual --type/model names"
  fi

  log "============================================================"
  log "[INFO] AI Forge cold model pull manifest mode"
  log "[INFO] MANIFEST_FILE=$MANIFEST_FILE"
  log "============================================================"

  load_manifest "$MANIFEST_FILE"
fi

MODEL_BUCKET="$(normalize_model_type "$MODEL_TYPE" || true)"
if [ -z "${MODEL_BUCKET:-}" ]; then
  echo "[ERROR] Missing or invalid --type. Use: lora, checkpoint, or diffusion"
  usage
  exit 1
fi

if [ -z "$MODEL_NAMES" ]; then
  echo "[ERROR] Missing model names. Example: xxx,yyy,zzz"
  usage
  exit 1
fi

REMOTE_DIR="$R2_COLD_REMOTE/$MODEL_BUCKET"
LOCAL_DIR="$COMFYUI_ROOT/models/$MODEL_BUCKET"

RCLONE_DRY_RUN_ARGS=()
if [ "$DRY_RUN" = true ]; then
  RCLONE_DRY_RUN_ARGS+=(--dry-run)
fi

mkdir -p "$LOCAL_DIR"

# ===== Core rclone connection =====
core_rclone_ensure_config "$RCLONE_CONF_SRC" "$RCLONE_CONF_DST"

log "============================================================"
log "[INFO] AI Forge cold model pull started"
if [ -n "$MANIFEST_FILE" ]; then
  log "[INFO] MODE=manifest"
  log "[INFO] MANIFEST_FILE=$MANIFEST_FILE"
else
  log "[INFO] MODE=manual"
fi
log "[INFO] MODEL_BUCKET=$MODEL_BUCKET"
log "[INFO] REMOTE_DIR=$REMOTE_DIR"
log "[INFO] LOCAL_DIR=$LOCAL_DIR"
log "[INFO] LOG_FILE=$LOG_FILE"
if [ "$DRY_RUN" = true ]; then
  log "[INFO] DRY RUN MODE ENABLED"
fi
log "============================================================"

resolve_remote_filename_case_insensitive() {
  local requested_filename="$1"

  core_rclone_lsf "$REMOTE_DIR" | awk -v target="$requested_filename" '
    BEGIN { target_lc = tolower(target) }
    tolower($0) == target_lc { print; exit }
  '
}

find_local_filename_case_insensitive() {
  local requested_filename="$1"

  find "$LOCAL_DIR" -maxdepth 1 -type f -printf '%f\n' 2>/dev/null | awk -v target="$requested_filename" '
    BEGIN { target_lc = tolower(target) }
    tolower($0) == target_lc { print; exit }
  '
}

pull_one_model() {
  local raw_name="$1"
  local model_name
  local requested_filename
  local local_existing_filename
  local remote_matched_filename
  local remote_file
  local local_file

  model_name="$(normalize_model_name "$raw_name")"

  if [ -z "$model_name" ]; then
    return 0
  fi

  requested_filename="$model_name.safetensors"

  local_existing_filename="$(find_local_filename_case_insensitive "$requested_filename")"
  if [ -n "$local_existing_filename" ]; then
    if [ "$local_existing_filename" != "$requested_filename" ]; then
      log "[INFO] local case-insensitive match found: requested=$requested_filename matched=$local_existing_filename"
    fi
    log "[SKIP] already exists locally: $LOCAL_DIR/$local_existing_filename"
    return 0
  fi

  remote_matched_filename="$(resolve_remote_filename_case_insensitive "$requested_filename")"
  if [ -z "$remote_matched_filename" ]; then
    log "[WARN] remote model not found: $REMOTE_DIR/$requested_filename"
    return 0
  fi

  if [ "$remote_matched_filename" != "$requested_filename" ]; then
    log "[INFO] remote case-insensitive match found: requested=$requested_filename matched=$remote_matched_filename"
  fi

  remote_file="$REMOTE_DIR/$remote_matched_filename"
  local_file="$LOCAL_DIR/$remote_matched_filename"

  log "[COPY] $remote_file -> $local_file"
  core_rclone_copyto "$remote_file" "$local_file" \
    --progress \
    --log-file "$LOG_FILE" \
    --log-level INFO \
    "${RCLONE_DRY_RUN_ARGS[@]}"

  log "[OK] pulled: $remote_matched_filename"
}

IFS=',' read -ra MODEL_ARRAY <<< "$MODEL_NAMES"
log "[INFO] Requested model count: ${#MODEL_ARRAY[@]}"

for name in "${MODEL_ARRAY[@]}"; do
  pull_one_model "$name"
done

log "============================================================"
log "[OK] AI Forge cold model pull completed"
log "[INFO] Log: $LOG_FILE"
log "============================================================"
