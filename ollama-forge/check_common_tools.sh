#!/usr/bin/env bash
set -euo pipefail

# Ollama Forge system prerequisite entry.
# Core owns common apt capabilities.
# Ollama remains an Ollama Forge dependency.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck disable=SC1091
source "${REPO_ROOT}/core/logging/log.sh"
# shellcheck disable=SC1091
source "${REPO_ROOT}/core/utils/common.sh"
# shellcheck disable=SC1091
source "${REPO_ROOT}/core/system/apt.sh"
ollama_log() {
  core_info "[Ollama Forge][check_common_tools] $*"
}

install_common_apt_packages() {
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
    pciutils
    lshw
    ffmpeg
    rclone
    unzip
    zip
  )

  core_apt_install_missing "${packages[@]}"
}

install_ollama_if_missing() {
  if core_command_exists ollama; then
    ollama_log "Ollama exists: $(ollama --version 2>/dev/null || true)"
    return 0
  fi

  ollama_log "Ollama missing. Installing Ollama..."
  curl -fsSL https://ollama.com/install.sh | sh
}

print_versions() {
  echo
  ollama_log "Versions:"
  echo "curl:        $(curl --version 2>/dev/null | head -n 1 || true)"
  echo "wget:        $(wget --version 2>/dev/null | head -n 1 || true)"
  echo "git:         $(git --version 2>/dev/null || true)"
  echo "ffmpeg:      $(ffmpeg -version 2>/dev/null | head -n 1 || true)"
  echo "rclone:      $(rclone version 2>/dev/null | head -n 1 || true)"
  echo "ollama:      $(ollama --version 2>/dev/null || true)"
}

main() {
  core_require_root
  install_common_apt_packages
  install_ollama_if_missing
  print_versions
  ollama_log "Common tools check completed."
}

main "$@"
