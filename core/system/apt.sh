#!/usr/bin/env bash

# Shared apt package inspection and installation.

_CORE_SYSTEM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${_CORE_SYSTEM_ROOT}/logging/log.sh"
# shellcheck disable=SC1091
source "${_CORE_SYSTEM_ROOT}/utils/common.sh"

core_apt_missing_packages() {
  local package

  for package in "$@"; do
    if ! dpkg-query -W -f='${Status}' "$package" 2>/dev/null \
      | grep -q '^install ok installed$'; then
      printf '%s\n' "$package"
    fi
  done
}

core_apt_install_missing() {
  core_require_root || return 1

  if ! core_command_exists apt-get || ! core_command_exists dpkg-query; then
    core_die "apt/dpkg is not available on this system."
    return 1
  fi

  local missing=()
  mapfile -t missing < <(core_apt_missing_packages "$@")

  if [ "${#missing[@]}" -eq 0 ]; then
    core_ok "All requested apt packages are already installed."
    return 0
  fi

  core_info "Installing missing apt packages: ${missing[*]}"
  DEBIAN_FRONTEND=noninteractive apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing[@]}"
  core_ok "Requested apt packages are ready."
}
