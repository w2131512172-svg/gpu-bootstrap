#!/usr/bin/env bash
set -euo pipefail

ENV_NAME="${ENV_NAME:-torch251-cu121}"
PY_VER="${PY_VER:-3.10}"
MINICONDA_DIR="${MINICONDA_DIR:-/root/miniconda3}"

export DEBIAN_FRONTEND=noninteractive

echo "== [1/5] apt packages =="
apt-get update
apt-get install -y \
  git \
  wget \
  aria2 \
  ffmpeg \
  libgl1 \
  libglib2.0-0 \
  build-essential \
  ca-certificates \
  bzip2

echo "== [2/5] ensure conda (miniconda) =="

# If conda isn't on PATH, but an installation directory exists, reuse it.
if ! command -v conda >/dev/null 2>&1; then
  if [ -x "${MINICONDA_DIR}/bin/conda" ]; then
    echo "conda not in PATH, but existing Miniconda found at: ${MINICONDA_DIR}"
    export PATH="${MINICONDA_DIR}/bin:${PATH}"
  else
    echo "conda not found, installing Miniconda to: ${MINICONDA_DIR}"
    mkdir -p /tmp/miniconda_install
    cd /tmp/miniconda_install

    wget -O miniconda.sh https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh
    bash miniconda.sh -b -p "${MINICONDA_DIR}"
    rm -f miniconda.sh

    export PATH="${MINICONDA_DIR}/bin:${PATH}"
  fi
fi

echo "== [3/5] conda env =="
# shellcheck disable=SC1091
source "$(conda info --base)/etc/profile.d/conda.sh"

conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main || true
conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r || true

if ! conda env list | awk '{print $1}' | grep -qx "$ENV_NAME"; then
  conda create -y -n "$ENV_NAME" "python=${PY_VER}"
fi

conda activate "$ENV_NAME"

command -v nvidia-smi >/dev/null && nvidia-smi || echo "[WARN] nvidia-smi not found"

echo "== [4/5] pip install torch/cu121 + xformers =="
python -m pip install -U pip setuptools wheel

python -m pip install \
  --index-url https://download.pytorch.org/whl/cu121 \
  torch==2.5.1+cu121 \
  torchvision==0.20.1+cu121 \
  torchaudio==2.5.1+cu121

python -m pip install xformers==0.0.27.post2 --no-deps

echo "== [5/5] healthcheck =="
python - <<'PY'
import torch, torchvision, torchaudio, xformers
print("torch      =", torch.__version__)
print("torchvision=", torchvision.__version__)
print("torchaudio =", torchaudio.__version__)
print("xformers   =", xformers.__version__)
print("cuda avail =", torch.cuda.is_available())
print("cuda ver   =", torch.version.cuda)
PY

echo "DONE."
