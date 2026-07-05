#!/usr/bin/env bash
set -euo pipefail

# EverForge / Ollama Forge common system tool checker
# Purpose:
#   - Check system-level apt packages used by Ollama Forge.
#   - Install only missing apt packages.
#   - Check/install shared CLI tools: rclone, cloudflared, ollama.
#
# Note:
#   This script intentionally does not touch the Open WebUI venv.
#   Python virtual environments isolate Python packages, not system commands.

log() {
  echo "[Ollama Forge][check_common_tools] $*"
}

need_root() {
  if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    echo "[Ollama Forge][check_common_tools][ERROR] Please run as root." >&2
    exit 1
  fi
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

install_missing_apt_packages() {
  local packages=(
    curl
    wget
    git
    ca-certificates
    build-essential
    net-tools
    iproute2
    htop
    tree
    nano
    python3.11
    python3.11-venv
    python3-pip
    pciutils
    lshw
    ffmpeg
    unzip
    zip
  )

  local missing=()
  local pkg

  log "Checking apt packages..."

  for pkg in "${packages[@]}"; do
    if dpkg -s "$pkg" >/dev/null 2>&1; then
      log "apt package exists: $pkg"
    else
      log "apt package missing: $pkg"
      missing+=("$pkg")
    fi
  done

  if [ "${#missing[@]}" -eq 0 ]; then
    log "All apt packages are already installed."
    return 0
  fi

  log "Installing missing apt packages: ${missing[*]}"
  apt update
  apt install -y "${missing[@]}"
}

install_rclone_if_missing() {
  if command_exists rclone; then
    log "rclone exists: $(rclone version 2>/dev/null | head -1 || true)"
    return 0
  fi

  log "rclone missing. Installing rclone..."
  curl https://rclone.org/install.sh | bash
}

install_cloudflared_if_missing() {
  if command_exists cloudflared; then
    log "cloudflared exists: $(cloudflared --version 2>/dev/null || true)"
    return 0
  fi

  log "cloudflared missing. Installing cloudflared..."
  wget -O /usr/local/bin/cloudflared \
    https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
  chmod +x /usr/local/bin/cloudflared
}

install_ollama_if_missing() {
  if command_exists ollama; then
    log "ollama exists: $(ollama --version 2>/dev/null || true)"
    return 0
  fi

  log "ollama missing. Installing Ollama..."
  curl -fsSL https://ollama.com/install.sh | sh
}

print_versions() {
  echo
  log "Versions:"
  echo "curl:        $(curl --version 2>/dev/null | head -1 || true)"
  echo "wget:        $(wget --version 2>/dev/null | head -1 || true)"
  echo "git:         $(git --version 2>/dev/null || true)"
  echo "python3.11:  $(python3.11 --version 2>/dev/null || true)"
  echo "pip3:        $(pip3 --version 2>/dev/null || true)"
  echo "ffmpeg:      $(ffmpeg -version 2>/dev/null | head -1 || true)"
  echo "rclone:      $(rclone version 2>/dev/null | head -1 || true)"
  echo "cloudflared: $(cloudflared --version 2>/dev/null || true)"
  echo "ollama:      $(ollama --version 2>/dev/null || true)"
}

main() {
  need_root
  install_missing_apt_packages
  install_rclone_if_missing
  install_cloudflared_if_missing
  install_ollama_if_missing
  print_versions
  log "Common tools check completed."
}

main "$@"
