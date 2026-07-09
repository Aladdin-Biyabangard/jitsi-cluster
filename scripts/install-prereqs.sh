#!/usr/bin/env bash
# Lokal maşın / Cloud Shell üçün deploy asılılıqlarını avtomatik quraşdırır.
# deploy.sh tərəfindən çağırılır — əl ilə işlətməyə ehtiyac yoxdur.

set -euo pipefail

_log()  { echo -e "\033[0;32m[+]\033[0m $*"; }
_warn() { echo -e "\033[1;33m[!]\033[0m $*"; }
_die()  { echo -e "\033[0;31m[x]\033[0m $*" >&2; exit 1; }

cmd_ok() {
  command -v "$1" >/dev/null 2>&1
}

run_apt() {
  if cmd_ok sudo; then
    sudo apt-get update -qq
    sudo apt-get install -y -qq "$@"
  elif [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    apt-get update -qq
    apt-get install -y -qq "$@"
  else
    _die "apt üçün sudo lazımdır: $*"
  fi
}

install_jq() {
  _log "jq quraşdırılır..."
  if cmd_ok apt-get; then
    run_apt jq
  elif cmd_ok brew; then
    brew install jq
  else
    _die "jq tapılmadı və avtomatik quraşdırıla bilmədi"
  fi
}

install_terraform_apt() {
  _log "Terraform quraşdırılır (apt)..."
  if cmd_ok sudo; then
    wget -qO- https://apt.releases.hashicorp.com/gpg \
      | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(grep -oP '(?<=UBUNTU_CODENAME=).*' /etc/os-release 2>/dev/null || lsb_release -cs 2>/dev/null || echo jammy) main" \
      | sudo tee /etc/apt/sources.list.d/hashicorp.list >/dev/null
    run_apt terraform
  elif [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    wget -qO- https://apt.releases.hashicorp.com/gpg \
      | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(grep -oP '(?<=UBUNTU_CODENAME=).*' /etc/os-release 2>/dev/null || echo jammy) main" \
      > /etc/apt/sources.list.d/hashicorp.list
    apt-get update -qq && apt-get install -y -qq terraform
  else
    _die "Terraform üçün sudo lazımdır"
  fi
}

install_terraform() {
  if cmd_ok brew; then
    _log "Terraform quraşdırılır (brew)..."
    brew install terraform
  elif cmd_ok apt-get; then
    install_terraform_apt
  else
    _die "Terraform tapılmadı. macOS: brew install terraform | Debian/Ubuntu: apt"
  fi
}

terraform_works() {
  terraform version >/dev/null 2>&1
}

jq_works() {
  jq --version >/dev/null 2>&1
}

persist_cloudshell_prereqs() {
  # Cloud Shell: yeni session-da terraform/itlər qalsın
  local marker='jitsi-deploy-prereqs'
  local file="${HOME}/.customize_environment"
  if [[ -n "${CLOUD_SHELL:-}" || -f "${HOME}/.cloudshell/boot-finished" ]]; then
    if [[ -f "${file}" ]] && grep -q "${marker}" "${file}" 2>/dev/null; then
      return 0
    fi
    _log "Cloud Shell: prereqs ~/.customize_environment-ə yazılır"
    cat >> "${file}" <<'EOF'

# jitsi-deploy-prereqs
if ! command -v terraform >/dev/null 2>&1; then
  sudo apt-get update -qq && sudo apt-get install -y -qq terraform jq 2>/dev/null || true
fi
EOF
  fi
}

ensure_deploy_prerequisites() {
  _log "Deploy asılılıqları yoxlanılır..."

  if ! cmd_ok curl; then
    if cmd_ok apt-get; then run_apt curl; else _die "curl lazımdır"; fi
  fi

  if ! cmd_ok ssh || ! cmd_ok scp; then
    if cmd_ok apt-get; then run_apt openssh-client; fi
  fi

  if ! jq_works; then
    install_jq
  fi

  if ! terraform_works; then
    install_terraform
  fi

  if ! terraform_works; then
    _die "Terraform quraşdırıldı amma işləmir — 'terraform version' yoxlayın"
  fi

  if ! cmd_ok gcloud; then
    _die "gcloud tapılmadı. Cloud Shell istifadə edin və ya: https://cloud.google.com/sdk/docs/install"
  fi

  persist_cloudshell_prereqs
  _log "Asılılıqlar hazırdır: terraform=$(terraform version | head -1) jq=$(jq --version)"
}

# Birbaşa çağırılsa
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  ensure_deploy_prerequisites
fi
