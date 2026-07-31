#!/usr/bin/env bash

# Dynamic GPU assignment for EverSpark Forge modules.
# Single-GPU systems keep their existing CUDA visibility unchanged.
# Multi-GPU systems isolate ComfyUI and Ollama on separate devices.

_CORE_GPU_ASSIGNMENT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${_CORE_GPU_ASSIGNMENT_ROOT}/logging/log.sh"
# shellcheck disable=SC1091
source "${_CORE_GPU_ASSIGNMENT_ROOT}/utils/common.sh"

core_gpu_count() {
  if ! core_command_exists nvidia-smi; then
    printf '%s\n' "0"
    return 0
  fi

  nvidia-smi --query-gpu=index --format=csv,noheader 2>/dev/null \
    | awk 'NF { count++ } END { print count + 0 }'
}

core_gpu_name_by_index() {
  local gpu_index="$1"

  nvidia-smi --id="$gpu_index" --query-gpu=name --format=csv,noheader 2>/dev/null \
    | head -n 1
}

core_gpu_assign_forge() {
  local forge_name="$1"
  local gpu_count gpu_index gpu_name

  gpu_count="$(core_gpu_count)"

  if [ "$gpu_count" -lt 2 ]; then
    core_info "Detected ${gpu_count} GPU(s); dedicated GPU assignment skipped for ${forge_name}."
    return 0
  fi

  case "$forge_name" in
    comfy|comfyui)
      gpu_index=0
      ;;
    ollama)
      gpu_index=1
      ;;
    *)
      core_die "Unknown Forge module for GPU assignment: $forge_name"
      return 1
      ;;
  esac

  gpu_name="$(core_gpu_name_by_index "$gpu_index" || true)"
  export CUDA_VISIBLE_DEVICES="$gpu_index"
  export EVERSPARK_ASSIGNED_GPU="$gpu_index"

  core_ok "GPU assigned: ${forge_name} -> GPU ${gpu_index} (${gpu_name:-unknown})"
}
