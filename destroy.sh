#!/usr/bin/env bash
# Bütün infrastrukturu silir (VM, IP, firewall, scheduler)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -f "${ROOT}/.env" ]]; then
  echo ".env lazımdır"
  exit 1
fi
set -a
# shellcheck disable=SC1091
source "${ROOT}/.env"
set +a

echo "⚠️  Bu ${GCP_PROJECT_ID} layihəsindəki Jitsi resurslarını SİLƏCƏK."
read -r -p "Davam? (yes yazın): " ans
[[ "${ans}" == "yes" ]] || exit 1

gcloud config set project "${GCP_PROJECT_ID}" >/dev/null

# Scheduler jobs
if gcloud scheduler jobs list --location="${GCP_REGION}" --project="${GCP_PROJECT_ID}" --format='value(name)' 2>/dev/null | grep -q jitsi; then
  while read -r job; do
    [[ -z "${job}" ]] && continue
    gcloud scheduler jobs delete "${job}" --location="${GCP_REGION}" --project="${GCP_PROJECT_ID}" --quiet || true
  done < <(gcloud scheduler jobs list --location="${GCP_REGION}" --project="${GCP_PROJECT_ID}" --format='value(name)' | grep jitsi || true)
fi

terraform -chdir="${ROOT}/terraform" destroy -auto-approve -input=false
echo "Silindi."
