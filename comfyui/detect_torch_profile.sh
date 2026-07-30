#!/usr/bin/env bash
set -euo pipefail

# ComfyUI Forge torch profile selector.
#
# Core reports GPU/CUDA facts. This Forge script owns the validated
# cu121/cu128 compatibility rule and the resulting profile decision.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck disable=SC1091
source "${REPO_ROOT}/core/hardware/gpu.sh"

profile_log() {
  echo "[detect_torch_profile] $*" >&2
}

if [ -n "${TORCH_PROFILE:-}" ]; then
  case "$TORCH_PROFILE" in
    cu121|cu128)
      profile_log "manual override TORCH_PROFILE=${TORCH_PROFILE}"
      echo "$TORCH_PROFILE"
      exit 0
      ;;
    *)
      profile_log "invalid TORCH_PROFILE=${TORCH_PROFILE}, expected cu121 or cu128"
      exit 1
      ;;
  esac
fi

core_gpu_require_nvidia_smi

GPU_NAME="$(core_gpu_name)"
BASE_CUDA="$(core_cuda_runtime_version)"
SM_RAW="$(core_gpu_compute_capability || true)"
SM_CODE="$(core_gpu_sm_code || true)"

# Some nvidia-smi versions do not expose compute_cap. Keep the Forge's
# validated name fallback for the architectures that require cu128.
if [ -z "$SM_CODE" ] \
  && echo "$GPU_NAME" | grep -Eq 'RTX 50|5090|5080|5070|5060|Blackwell|B200|B100'; then
  SM_CODE="120"
fi

NEW_ARCH_GPU=0
if [ -n "$SM_CODE" ] && core_version_ge "$SM_CODE" "120"; then
  NEW_ARCH_GPU=1
fi

BASE_CUDA_128_PLUS=0
if [ -n "$BASE_CUDA" ] && core_version_ge "$BASE_CUDA" "12.8"; then
  BASE_CUDA_128_PLUS=1
fi

profile_log "gpu_name=${GPU_NAME:-unknown}"
profile_log "sm_raw=${SM_RAW:-unknown}"
profile_log "sm_code=${SM_CODE:-unknown}"
profile_log "base_cuda=${BASE_CUDA:-unknown}"
profile_log "new_arch_gpu=${NEW_ARCH_GPU}"
profile_log "base_cuda_128_plus=${BASE_CUDA_128_PLUS}"

if [ "$NEW_ARCH_GPU" = "1" ] && [ "$BASE_CUDA_128_PLUS" = "1" ]; then
  profile_log "selected profile=cu128"
  echo "cu128"
else
  profile_log "selected profile=cu121"
  echo "cu121"
fi
