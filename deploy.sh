#!/usr/bin/env bash
# ============================================================
# jitsi-deploy — bir əmrlə 11 VM Jitsi + Jibri + Bunny
#
# İstifadə:
#   cp .env.example .env   # doldurun
#   ./deploy.sh
# ============================================================

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${ROOT}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log()  { echo -e "${GREEN}[+]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[x]${NC} $*" >&2; }
die()  { err "$*"; exit 1; }

# ---------- Load .env ----------
if [[ ! -f "${ROOT}/.env" ]]; then
  die ".env tapılmadı. Əvvəl: cp .env.example .env && nano .env"
fi
set -a
# shellcheck disable=SC1091
source "${ROOT}/.env"
set +a

: "${GCP_PROJECT_ID:?GCP_PROJECT_ID .env-də lazımdır}"
: "${DOMAIN:?DOMAIN .env-də lazımdır}"
: "${ADMIN_EMAIL:?ADMIN_EMAIL .env-də lazımdır}"

GCP_REGION="${GCP_REGION:-europe-west1}"
GCP_ZONE="${GCP_ZONE:-europe-west1-b}"
GCP_NETWORK="${GCP_NETWORK:-default}"
JIBRI_COUNT="${JIBRI_COUNT:-9}"
CONTROL_MACHINE_TYPE="${CONTROL_MACHINE_TYPE:-e2-standard-4}"
JVB_MACHINE_TYPE="${JVB_MACHINE_TYPE:-e2-standard-16}"
JIBRI_MACHINE_TYPE="${JIBRI_MACHINE_TYPE:-e2-standard-4}"
CONTROL_DISK_GB="${CONTROL_DISK_GB:-50}"
JVB_DISK_GB="${JVB_DISK_GB:-50}"
JIBRI_DISK_GB="${JIBRI_DISK_GB:-30}"
ENABLE_SCHEDULE="${ENABLE_SCHEDULE:-true}"
SCHEDULE_START_UTC="${SCHEDULE_START_UTC:-03:30}"
SCHEDULE_STOP_UTC="${SCHEDULE_STOP_UTC:-06:05}"
SCHEDULE_TIMEZONE="${SCHEDULE_TIMEZONE:-UTC}"
BUNNY_STORAGE_ZONE="${BUNNY_STORAGE_ZONE:-}"
BUNNY_STORAGE_PASSWORD="${BUNNY_STORAGE_PASSWORD:-}"
BUNNY_STORAGE_REGION="${BUNNY_STORAGE_REGION:-de}"
BUNNY_CDN_HOSTNAME="${BUNNY_CDN_HOSTNAME:-}"
BUNNY_UPLOAD_PATH="${BUNNY_UPLOAD_PATH:-recordings}"

hhmm_to_cron() {
  # HH:MM → "MM HH * * *"
  local t="$1"
  local hh="${t%%:*}"
  local mm="${t##*:}"
  echo "${mm} ${hh} * * *"
}

SCHEDULE_START_CRON="$(hhmm_to_cron "${SCHEDULE_START_UTC}")"
SCHEDULE_STOP_CRON="$(hhmm_to_cron "${SCHEDULE_STOP_UTC}")"

# ---------- Prerequisites ----------
need_cmd() { command -v "$1" >/dev/null 2>&1 || die "'$1' lazımdır. Quraşdırın və yenidən cəhd edin."; }
need_cmd gcloud
need_cmd terraform
need_cmd jq
need_cmd ssh
need_cmd scp
need_cmd curl

log "GCP project: ${GCP_PROJECT_ID}"
gcloud config set project "${GCP_PROJECT_ID}" >/dev/null

log "API-lər aktivləşdirilir..."
gcloud services enable \
  compute.googleapis.com \
  cloudscheduler.googleapis.com \
  iam.googleapis.com \
  appengine.googleapis.com \
  --project="${GCP_PROJECT_ID}" >/dev/null

# Cloud Scheduler bəzi regionlarda App Engine app tələb edir
if [[ "${ENABLE_SCHEDULE}" == "true" ]]; then
  if ! gcloud app describe --project="${GCP_PROJECT_ID}" &>/dev/null; then
    log "App Engine app yaradılır (scheduler üçün)..."
    gcloud app create --region="${GCP_REGION}" --project="${GCP_PROJECT_ID}" 2>/dev/null \
      || warn "App Engine create uğursuz/artıq var — davam edilir"
  fi
fi

# ---------- SSH key ----------
SECRETS_DIR="${ROOT}/secrets"
mkdir -p "${SECRETS_DIR}"
chmod 700 "${SECRETS_DIR}"

if [[ -n "${SSH_PUBLIC_KEY_PATH:-}" && -f "${SSH_PUBLIC_KEY_PATH}" ]]; then
  SSH_PUB="$(cat "${SSH_PUBLIC_KEY_PATH}")"
  SSH_PRIV="${SSH_PUBLIC_KEY_PATH%.pub}"
  [[ -f "${SSH_PRIV}" ]] || die "Private key tapılmadı: ${SSH_PRIV}"
else
  SSH_PRIV="${SECRETS_DIR}/deploy_key"
  SSH_PUB_FILE="${SECRETS_DIR}/deploy_key.pub"
  if [[ ! -f "${SSH_PRIV}" ]]; then
    log "SSH açarı yaradılır..."
    ssh-keygen -t ed25519 -N "" -f "${SSH_PRIV}" -C "jitsi-deploy" >/dev/null
  fi
  SSH_PUB="$(cat "${SSH_PUB_FILE}")"
fi

# ---------- Terraform ----------
mkdir -p "${ROOT}/terraform/generated"
TF_DIR="${ROOT}/terraform"

cat > "${TF_DIR}/terraform.tfvars" <<TFVARS
project_id            = "${GCP_PROJECT_ID}"
region                = "${GCP_REGION}"
zone                  = "${GCP_ZONE}"
network               = "${GCP_NETWORK}"
domain                = "${DOMAIN}"
admin_email           = "${ADMIN_EMAIL}"
ssh_public_key        = "${SSH_PUB}"
jibri_count           = ${JIBRI_COUNT}
control_machine_type  = "${CONTROL_MACHINE_TYPE}"
jvb_machine_type      = "${JVB_MACHINE_TYPE}"
jibri_machine_type    = "${JIBRI_MACHINE_TYPE}"
control_disk_gb       = ${CONTROL_DISK_GB}
jvb_disk_gb           = ${JVB_DISK_GB}
jibri_disk_gb         = ${JIBRI_DISK_GB}
enable_schedule       = ${ENABLE_SCHEDULE}
schedule_start_cron   = "${SCHEDULE_START_CRON}"
schedule_stop_cron    = "${SCHEDULE_STOP_CRON}"
schedule_timezone     = "${SCHEDULE_TIMEZONE}"
bunny_storage_zone    = "${BUNNY_STORAGE_ZONE}"
bunny_storage_password = "${BUNNY_STORAGE_PASSWORD}"
bunny_storage_region  = "${BUNNY_STORAGE_REGION}"
bunny_cdn_hostname    = "${BUNNY_CDN_HOSTNAME}"
bunny_upload_path     = "${BUNNY_UPLOAD_PATH}"
TFVARS

log "Terraform init..."
terraform -chdir="${TF_DIR}" init -upgrade -input=false

log "Terraform apply (11 VM)..."
terraform -chdir="${TF_DIR}" apply -auto-approve -input=false

CONTROL_PUBLIC_IP="$(terraform -chdir="${TF_DIR}" output -raw control_public_ip)"
JVB_PUBLIC_IP="$(terraform -chdir="${TF_DIR}" output -raw jvb_public_ip)"
CONTROL_PRIVATE_IP="$(terraform -chdir="${TF_DIR}" output -raw control_private_ip)"
JVB_PRIVATE_IP="$(terraform -chdir="${TF_DIR}" output -raw jvb_private_ip)"

OUTPUTS_JSON="${TF_DIR}/generated/outputs.json"
[[ -f "${OUTPUTS_JSON}" ]] || die "outputs.json yoxdur"

JVB_PASSWORD="$(jq -r '.secrets.jvb_password' "${OUTPUTS_JSON}")"
JICOFO_PASSWORD="$(jq -r '.secrets.jicofo_password' "${OUTPUTS_JSON}")"
JIBRI_RECORDER_PASS="$(jq -r '.secrets.jibri_recorder_pass' "${OUTPUTS_JSON}")"
JIBRI_XMPP_PASS="$(jq -r '.secrets.jibri_xmpp_pass' "${OUTPUTS_JSON}")"
TURN_SECRET="$(jq -r '.secrets.turn_secret' "${OUTPUTS_JSON}")"

mapfile -t JIBRI_NAMES < <(jq -r '.jibri_names[]' "${OUTPUTS_JSON}")

log "Control IP: ${CONTROL_PUBLIC_IP}"
log "JVB IP:     ${JVB_PUBLIC_IP}"
log "Jibri:      ${#JIBRI_NAMES[@]} ədəd"

# ---------- Wait for SSH ----------
ssh_opts=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -i "${SSH_PRIV}")

wait_ssh() {
  local host="$1" name="$2"
  log "SSH gözlənilir: ${name} (${host})..."
  for i in $(seq 1 60); do
    if ssh "${ssh_opts[@]}" "ubuntu@${host}" "echo ok" >/dev/null 2>&1; then
      log "SSH hazır: ${name}"
      return 0
    fi
    sleep 5
  done
  die "SSH timeout: ${name} (${host})"
}

# Ephemeral IPs for jibri — get from gcloud
get_instance_ip() {
  gcloud compute instances describe "$1" \
    --project="${GCP_PROJECT_ID}" \
    --zone="${GCP_ZONE}" \
    --format='get(networkInterfaces[0].accessConfigs[0].natIP)'
}

wait_ssh "${CONTROL_PUBLIC_IP}" "meet-control"
wait_ssh "${JVB_PUBLIC_IP}" "meet-jvb"

JIBRI_IP_LIST=()
for name in "${JIBRI_NAMES[@]}"; do
  ip="$(get_instance_ip "${name}")"
  JIBRI_IP_LIST+=("${ip}")
  wait_ssh "${ip}" "${name}"
done

# ---------- Sync scripts ----------
remote_sync() {
  local host="$1"
  ssh "${ssh_opts[@]}" "ubuntu@${host}" "sudo mkdir -p /tmp/jitsi-deploy && sudo chown ubuntu:ubuntu /tmp/jitsi-deploy"
  scp -q "${ssh_opts[@]}" -r \
    "${ROOT}/scripts" "${ROOT}/config" \
    "ubuntu@${host}:/tmp/jitsi-deploy/"
  ssh "${ssh_opts[@]}" "ubuntu@${host}" "chmod +x /tmp/jitsi-deploy/scripts/*.sh"
}

log "Skriptlər control-a kopyalanır..."
remote_sync "${CONTROL_PUBLIC_IP}"

log "meet-control quraşdırılır..."
ssh "${ssh_opts[@]}" "ubuntu@${CONTROL_PUBLIC_IP}" "sudo bash -s" <<REMOTE
set -euo pipefail
export DOMAIN='${DOMAIN}'
export ADMIN_EMAIL='${ADMIN_EMAIL}'
export JVB_PASSWORD='${JVB_PASSWORD}'
export JICOFO_PASSWORD='${JICOFO_PASSWORD}'
export JIBRI_RECORDER_PASS='${JIBRI_RECORDER_PASS}'
export JIBRI_XMPP_PASS='${JIBRI_XMPP_PASS}'
export TURN_SECRET='${TURN_SECRET}'
export JVB_PUBLIC_IP='${JVB_PUBLIC_IP}'
export JVB_PRIVATE_IP='${JVB_PRIVATE_IP}'
export CONTROL_PUBLIC_IP='${CONTROL_PUBLIC_IP}'
bash /tmp/jitsi-deploy/scripts/setup-control.sh
REMOTE

# Prosody: allow remote c2s (bind all interfaces)
ssh "${ssh_opts[@]}" "ubuntu@${CONTROL_PUBLIC_IP}" "sudo bash -s" <<'REMOTE'
set -euo pipefail
# Ensure c2s listens on all interfaces
if ! grep -q 'c2s_interfaces' /etc/prosody/prosody.cfg.lua 2>/dev/null; then
  sed -i '/^-- c2s_ports/a c2s_interfaces = { "*" }' /etc/prosody/prosody.cfg.lua 2>/dev/null || true
fi
# component interfaces
if grep -q 'component_ports' /etc/prosody/prosody.cfg.lua; then
  grep -q 'component_interfaces' /etc/prosody/prosody.cfg.lua || \
    sed -i '/component_ports/a component_interfaces = { "*" }' /etc/prosody/prosody.cfg.lua || true
fi
systemctl restart prosody
REMOTE

log "meet-jvb quraşdırılır..."
remote_sync "${JVB_PUBLIC_IP}"
ssh "${ssh_opts[@]}" "ubuntu@${JVB_PUBLIC_IP}" "sudo bash -s" <<REMOTE
set -euo pipefail
export DOMAIN='${DOMAIN}'
export CONTROL_PRIVATE_IP='${CONTROL_PRIVATE_IP}'
export JVB_PASSWORD='${JVB_PASSWORD}'
export JVB_PUBLIC_IP='${JVB_PUBLIC_IP}'
bash /tmp/jitsi-deploy/scripts/setup-jvb.sh
REMOTE

# ---------- Jibris (parallel) ----------
log "Jibri VM-lər quraşdırılır (${#JIBRI_NAMES[@]} ədəd, parallel)..."
PIDS=()
for idx in "${!JIBRI_NAMES[@]}"; do
  name="${JIBRI_NAMES[$idx]}"
  ip="${JIBRI_IP_LIST[$idx]}"
  (
    remote_sync "${ip}"
    ssh "${ssh_opts[@]}" "ubuntu@${ip}" "sudo bash -s" <<REMOTE
set -euo pipefail
export DOMAIN='${DOMAIN}'
export CONTROL_PRIVATE_IP='${CONTROL_PRIVATE_IP}'
export JIBRI_RECORDER_PASS='${JIBRI_RECORDER_PASS}'
export JIBRI_XMPP_PASS='${JIBRI_XMPP_PASS}'
export JIBRI_NICKNAME='${name}'
export BUNNY_STORAGE_ZONE='${BUNNY_STORAGE_ZONE}'
export BUNNY_STORAGE_PASSWORD='${BUNNY_STORAGE_PASSWORD}'
export BUNNY_STORAGE_REGION='${BUNNY_STORAGE_REGION}'
export BUNNY_CDN_HOSTNAME='${BUNNY_CDN_HOSTNAME}'
export BUNNY_UPLOAD_PATH='${BUNNY_UPLOAD_PATH}'
bash /tmp/jitsi-deploy/scripts/setup-jibri.sh
REMOTE
  ) > "${SECRETS_DIR}/setup-${name}.log" 2>&1 &
  PIDS+=($!)
done

FAIL=0
for pid in "${PIDS[@]}"; do
  wait "${pid}" || FAIL=1
done
[[ "${FAIL}" -eq 0 ]] || warn "Bəzi Jibri setup-ları xəta verdi — secrets/setup-jibri-*.log baxın"

# ---------- DNS (optional) ----------
if [[ -n "${CLOUDFLARE_API_TOKEN:-}" && -n "${CLOUDFLARE_ZONE_ID:-}" ]]; then
  log "Cloudflare DNS yenilənir..."
  export CLOUDFLARE_API_TOKEN CLOUDFLARE_ZONE_ID
  export CLOUDFLARE_RECORD_NAME="${CLOUDFLARE_RECORD_NAME:-${DOMAIN}}"
  export CONTROL_PUBLIC_IP
  bash "${ROOT}/scripts/update-dns-cloudflare.sh" || warn "DNS update uğursuz"
else
  warn "Cloudflare boşdur — DNS-i əl ilə qoyun:"
  warn "  ${DOMAIN}  A  ${CONTROL_PUBLIC_IP}"
fi

# ---------- Scheduler for all VMs ----------
if [[ "${ENABLE_SCHEDULE}" == "true" ]]; then
  log "Cloud Scheduler (bütün VM-lər)..."
  SA_EMAIL="$(gcloud iam service-accounts list \
    --project="${GCP_PROJECT_ID}" \
    --filter="email:jitsi-scheduler@" \
    --format='value(email)' | head -1)"
  if [[ -n "${SA_EMAIL}" ]]; then
    export GCP_PROJECT_ID GCP_ZONE GCP_REGION
    export SCHEDULE_START_CRON SCHEDULE_STOP_CRON SCHEDULE_TIMEZONE
    export SCHEDULER_SA_EMAIL="${SA_EMAIL}"
    bash "${ROOT}/scripts/install-scheduler-jobs.sh" || warn "Scheduler jobs qismən uğursuz"
  else
    warn "jitsi-scheduler SA tapılmadı — terraform schedule yoxlayın"
  fi
fi

# ---------- Summary ----------
cat <<EOF

${GREEN}========================================${NC}
${GREEN}  Deploy tamamlandı${NC}
${GREEN}========================================${NC}

  URL:              https://${DOMAIN}
  meet-control IP:  ${CONTROL_PUBLIC_IP}
  meet-jvb IP:      ${JVB_PUBLIC_IP}
  Jibri sayı:       ${#JIBRI_NAMES[@]}

  DNS (vacib):
    ${DOMAIN}  →  A  →  ${CONTROL_PUBLIC_IP}
    (JVB media üçün əlavə DNS lazım deyil — IP mapping avtomatikdir)

  Recording:
    Meeting-də "..." → Start recording
    Bitəndə MP4 → Bunny (${BUNNY_STORAGE_ZONE}/${BUNNY_UPLOAD_PATH}/...)
    Upload OK → serverdən silinir

  Schedule (${ENABLE_SCHEDULE}):
    Start UTC: ${SCHEDULE_START_UTC}  (cron: ${SCHEDULE_START_CRON})
    Stop  UTC: ${SCHEDULE_STOP_UTC}   (cron: ${SCHEDULE_STOP_CRON})

  Manual start/stop:
    GCP_PROJECT_ID=${GCP_PROJECT_ID} GCP_ZONE=${GCP_ZONE} \\
      ./scripts/schedule-all.sh start

  Secrets:
    ${OUTPUTS_JSON}
    ${SSH_PRIV}

${YELLOW}DNS yayımlandıqdan sonra SSL üçün:${NC}
  gcloud compute ssh meet-control --zone=${GCP_ZONE} --project=${GCP_PROJECT_ID} -- \\
    "sudo /usr/share/jitsi-meet/scripts/install-letsencrypt-cert.sh ${ADMIN_EMAIL} ${DOMAIN}"

EOF
