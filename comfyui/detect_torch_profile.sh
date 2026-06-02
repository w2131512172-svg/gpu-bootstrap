#!/usr/bin/env bash
set -euo pipefail

# AI Forge torch profile detector
#
# Current validated matrix:
#   RTX 5090 + CUDA 12.1 base + bootstrap-cu121 = OK
#   RTX 5090 + CUDA 12.8 base + bootstrap-cu121 = FAIL
#   RTX 5090 + CUDA 12.8 base + bootstrap-cu128 = OK
#   A100     + CUDA 12.8 base + bootstrap-cu121 = OK
#   RTX PRO 5000 Blackwell + CUDA 12.8 base + bootstrap-cu128 = OK
#
# Rule v0.3:
#   New architecture GPU + CUDA 12.8+ base image -> cu128
#   Otherwise                                      -> cu121
#
# Manual override:
#   TORCH_PROFILE=cu128 bash forge_start.sh
#   TORCH_PROFILE=cu121 bash forge_start.sh

log() {
  echo "[detect_torch_profile] $*" >&2
}

if [ -n "${TORCH_PROFILE:-}" ]; then
  case "$TORCH_PROFILE" in
    cu121|cu128)
      log "manual override TORCH_PROFILE=${TORCH_PROFILE}"
      echo "$TORCH_PROFILE"
      exit 0
      ;;
    *)
      log "invalid TORCH_PROFILE=${TORCH_PROFILE}, expected cu121 or cu128"
      exit 1
      ;;
  esac
fi

GPU_NAME="$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -n1 || true)"

# Base image CUDA version, not host driver CUDA version.
# nvidia-smi reports driver CUDA capability, so do not use it for BASE_CUDA.
BASE_CUDA=""

# 1) Prefer explicit version files when available.
if [ -f /usr/local/cuda/version.txt ]; then
  BASE_CUDA="$(grep -oE '[0-9]+\.[0-9]+' /usr/local/cuda/version.txt | head -n1 || true)"
fi

# 2) Runtime images may not include nvcc, but devel images usually do.
if [ -z "$BASE_CUDA" ] && command -v nvcc >/dev/null 2>&1; then
  BASE_CUDA="$(nvcc --version 2>/dev/null | grep -oE 'release [0-9]+\.[0-9]+' | awk '{print $2}' | head -n1 || true)"
fi

# 3) CUDA runtime images often expose /usr/local/cuda-12.8 but no version.txt/nvcc.
if [ -z "$BASE_CUDA" ]; then
  BASE_CUDA="$(find /usr/local -maxdepth 1 -type d -regextype posix-extended -regex '.*/cuda-[0-9]+\.[0-9]+' 2>/dev/null \
    | sed -E 's#.*/cuda-([0-9]+\.[0-9]+).*#\1#' \
    | sort -V \
    | tail -n1 || true)"
fi

# SM / compute capability.
# Prefer nvidia-smi compute_cap so this still works before bootstrap installs Python.
SM_RAW="$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | head -n1 || true)"
SM_CODE=""
if echo "$SM_RAW" | grep -Eq '^[0-9]+\.[0-9]+'; then
  SM_MAJOR="$(echo "$SM_RAW" | cut -d. -f1)"
  SM_MINOR="$(echo "$SM_RAW" | cut -d. -f2 | grep -oE '^[0-9]+' || true)"
  if [ -n "$SM_MAJOR" ] && [ -n "$SM_MINOR" ]; then
    SM_CODE=$((SM_MAJOR * 10 + SM_MINOR))
  fi
fi

# Some nvidia-smi versions do not expose compute_cap. Fall back to known names.
if [ -z "$SM_CODE" ]; then
  if echo "$GPU_NAME" | grep -Eq 'RTX 50|5090|5080|5070|5060|Blackwell|B200|B100'; then
    SM_CODE="120"
  fi
fi

NEW_ARCH_GPU=0
if [ -n "$SM_CODE" ]; then
  if awk "BEGIN {exit !($SM_CODE >= 120)}"; then
    NEW_ARCH_GPU=1
  fi
else
  # Unknown architecture should stay on the stable line unless manually overridden.
  NEW_ARCH_GPU=0
fi

BASE_CUDA_128_PLUS=0
if [ -n "$BASE_CUDA" ]; then
  if awk "BEGIN {exit !($BASE_CUDA >= 12.8)}"; then
    BASE_CUDA_128_PLUS=1
  fi
fi

log "gpu_name=${GPU_NAME:-unknown}"
log "sm_raw=${SM_RAW:-unknown}"
log "sm_code=${SM_CODE:-unknown}"
log "base_cuda=${BASE_CUDA:-unknown}"
log "new_arch_gpu=${NEW_ARCH_GPU}"
log "base_cuda_128_plus=${BASE_CUDA_128_PLUS}"

if [ "$NEW_ARCH_GPU" = "1" ] && [ "$BASE_CUDA_128_PLUS" = "1" ]; then
  log "selected profile=cu128"
  echo "cu128"
else
  log "selected profile=cu121"
  echo "cu121"
fi
