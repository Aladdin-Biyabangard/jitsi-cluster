#!/usr/bin/env bash
# GCP-də artıq olan Jitsi resurslarını Terraform state-ə import edir.
# Yarımçıq destroy / itmiş tfstate / Cloud Shell yenidən deploy zamanı 409 alreadyExists həll edir.
#
# İstifadə (deploy.sh çağırır):
#   GCP_PROJECT_ID=... GCP_REGION=... GCP_ZONE=... RECORDER_COUNT=2 ENABLE_SCHEDULE=true \
#     bash scripts/tf-import-existing.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="${ROOT}/terraform"

: "${GCP_PROJECT_ID:?}"
GCP_REGION="${GCP_REGION:-europe-west1}"
GCP_ZONE="${GCP_ZONE:-europe-west1-b}"
RECORDER_COUNT="${RECORDER_COUNT:-2}"
ENABLE_SCHEDULE="${ENABLE_SCHEDULE:-true}"

_log()  { echo -e "\033[0;32m[+]\033[0m $*"; }
_warn() { echo -e "\033[1;33m[!]\033[0m $*"; }

in_state() {
  terraform -chdir="${TF_DIR}" state show "$1" >/dev/null 2>&1
}

tf_import() {
  local addr="$1" id="$2"
  if in_state "${addr}"; then
    return 0
  fi
  _log "Import: ${addr}"
  if terraform -chdir="${TF_DIR}" import -input=false "${addr}" "${id}" >/dev/null 2>&1; then
    return 0
  fi
  _warn "Import alınmadı (yoxdur və ya uyğunsuz): ${addr}"
  return 0
}

addr_exists() {
  gcloud compute addresses describe "$1" \
    --project="${GCP_PROJECT_ID}" --region="${GCP_REGION}" \
    --format='value(name)' >/dev/null 2>&1
}

fw_exists() {
  gcloud compute firewall-rules describe "$1" \
    --project="${GCP_PROJECT_ID}" \
    --format='value(name)' >/dev/null 2>&1
}

inst_exists() {
  gcloud compute instances describe "$1" \
    --project="${GCP_PROJECT_ID}" --zone="${GCP_ZONE}" \
    --format='value(name)' >/dev/null 2>&1
}

sa_exists() {
  gcloud iam service-accounts describe \
    "jitsi-scheduler@${GCP_PROJECT_ID}.iam.gserviceaccount.com" \
    --project="${GCP_PROJECT_ID}" \
    --format='value(email)' >/dev/null 2>&1
}

_log "Mövcud GCP resursları Terraform state-ə yoxlanır/import edilir..."

if addr_exists "jitsi-control-ip"; then
  tf_import 'google_compute_address.control' \
    "projects/${GCP_PROJECT_ID}/regions/${GCP_REGION}/addresses/jitsi-control-ip"
fi
if addr_exists "jitsi-jvb-ip"; then
  tf_import 'google_compute_address.jvb' \
    "projects/${GCP_PROJECT_ID}/regions/${GCP_REGION}/addresses/jitsi-jvb-ip"
fi

if fw_exists "jitsi-allow-web"; then
  tf_import 'google_compute_firewall.jitsi_web' \
    "projects/${GCP_PROJECT_ID}/global/firewalls/jitsi-allow-web"
fi
if fw_exists "jitsi-allow-ssh"; then
  tf_import 'google_compute_firewall.jitsi_ssh' \
    "projects/${GCP_PROJECT_ID}/global/firewalls/jitsi-allow-ssh"
fi
if fw_exists "jitsi-allow-media"; then
  tf_import 'google_compute_firewall.jitsi_media' \
    "projects/${GCP_PROJECT_ID}/global/firewalls/jitsi-allow-media"
fi
if fw_exists "jitsi-allow-internal"; then
  tf_import 'google_compute_firewall.jitsi_internal' \
    "projects/${GCP_PROJECT_ID}/global/firewalls/jitsi-allow-internal"
fi

if inst_exists "meet-control"; then
  tf_import 'google_compute_instance.control' \
    "projects/${GCP_PROJECT_ID}/zones/${GCP_ZONE}/instances/meet-control"
fi
if inst_exists "meet-jvb"; then
  tf_import 'google_compute_instance.jvb' \
    "projects/${GCP_PROJECT_ID}/zones/${GCP_ZONE}/instances/meet-jvb"
fi

i=0
while (( i < RECORDER_COUNT )); do
  name="recorder-$((i + 1))"
  if inst_exists "${name}"; then
    tf_import "google_compute_instance.jibri[${i}]" \
      "projects/${GCP_PROJECT_ID}/zones/${GCP_ZONE}/instances/${name}"
  fi
  old="jibri-$((i + 1))"
  if inst_exists "${old}" && ! inst_exists "${name}"; then
    _warn "Köhnə VM ${old} var — əl ilə silin (indi recorder-* gözlənilir)"
  fi
  i=$((i + 1))
done

if [[ "${ENABLE_SCHEDULE}" == "true" ]] && sa_exists; then
  tf_import 'google_service_account.scheduler[0]' \
    "projects/${GCP_PROJECT_ID}/serviceAccounts/jitsi-scheduler@${GCP_PROJECT_ID}.iam.gserviceaccount.com"
fi

_log "Import yoxlaması bitdi"
