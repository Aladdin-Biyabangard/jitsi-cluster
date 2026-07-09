#!/usr/bin/env bash
# Shared helpers for remote setup scripts

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}[+]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[x]${NC} $*" >&2; }

require_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    err "Root lazımdır: sudo $0"
    exit 1
  fi
}

wait_apt() {
  while fuser --quiet /var/lib/dpkg/lock-frontend; do
    warn "apt kilidi gözlənilir..."
    sleep 5
  done
}

install_base() {
  export DEBIAN_FRONTEND=noninteractive
  wait_apt
  apt-get update -qq
  apt-get install -y -qq \
    apt-transport-https ca-certificates curl gnupg2 \
    software-properties-common ufw jq unzip \
    dnsutils openssl
}

add_jitsi_repo() {
  if [[ ! -f /usr/share/keyrings/jitsi-keyring.gpg ]]; then
    curl -fsSL https://download.jitsi.org/jitsi-key.gpg.key \
      | gpg --dearmor -o /usr/share/keyrings/jitsi-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/jitsi-keyring.gpg] https://download.jitsi.org stable/" \
      > /etc/apt/sources.list.d/jitsi-stable.list
    apt-get update -qq
  fi
}

apply_sysctl() {
  local src="${1:-/tmp/jitsi-deploy/config/sysctl-jitsi.conf}"
  if [[ -f "$src" ]]; then
    cp "$src" /etc/sysctl.d/99-jitsi.conf
    sysctl -p /etc/sysctl.d/99-jitsi.conf >/dev/null || true
  fi
}

ufw_base() {
  ufw --force reset >/dev/null 2>&1 || true
  ufw default deny incoming
  ufw default allow outgoing
  ufw allow OpenSSH
}

metadata() {
  # GCP instance metadata
  curl -s -H "Metadata-Flavor: Google" \
    "http://metadata.google.internal/computeMetadata/v1/instance/attributes/${1}" 2>/dev/null || true
}

private_ip() {
  hostname -I | awk '{print $1}'
}

public_ip() {
  curl -4 -s --max-time 5 ifconfig.me || curl -4 -s --max-time 5 icanhazip.com || true
}
