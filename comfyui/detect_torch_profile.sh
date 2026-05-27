#!/usr/bin/env bash
set -euo pipefail

GPU_NAME="$(nvidia-smi --query-gpu=name --format=csv,noheader | head -n1 || true)"
GPU_CAP="$(python - <<'PY' 2>/dev/null || true
import subprocess,re
try:
    out=subprocess.check_output(['nvidia-smi']).decode()
    m=re.search(r'CUDA Version: ([0-9.]+)',out)
    print(m.group(1) if m else '')
except Exception:
    pass
PY
)"

if echo "$GPU_NAME" | grep -Eq '5090|5080|5070|5060'; then
  echo 'cu128'
  exit 0
fi

if [ -n "$GPU_CAP" ]; then
  awk "BEGIN {exit !($GPU_CAP >= 12.8)}" && {
    echo 'cu128'
    exit 0
  }
fi

echo 'cu121'
