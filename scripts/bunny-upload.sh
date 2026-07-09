#!/usr/bin/env bash
# Recording bitəndən sonra: Bunny Storage-ə yüklə → uğurlu olsa lokal sil
# Jibri finalize_recording.sh tərəfindən çağırılır

set -euo pipefail

LOG_TAG="bunny-upload"
log()  { echo "[$(date -Iseconds)] [${LOG_TAG}] $*"; }
err()  { echo "[$(date -Iseconds)] [${LOG_TAG}] ERROR: $*" >&2; }

ENV_FILE="${BUNNY_ENV_FILE:-/opt/jitsi-jibri/bunny.env}"
if [[ -f "${ENV_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
fi

RECORDING_DIR="${1:-}"
if [[ -z "${RECORDING_DIR}" || ! -d "${RECORDING_DIR}" ]]; then
  err "Recording directory yoxdur: ${RECORDING_DIR}"
  exit 1
fi

: "${BUNNY_STORAGE_ZONE:?BUNNY_STORAGE_ZONE required}"
: "${BUNNY_STORAGE_PASSWORD:?BUNNY_STORAGE_PASSWORD required}"

REGION="${BUNNY_STORAGE_REGION:-de}"
UPLOAD_PATH="${BUNNY_UPLOAD_PATH:-recordings}"
CDN_HOST="${BUNNY_CDN_HOSTNAME:-}"

if [[ "${REGION}" == "de" || "${REGION}" == "" ]]; then
  STORAGE_HOST="storage.bunnycdn.com"
else
  STORAGE_HOST="${REGION}.storage.bunnycdn.com"
fi

# Find mp4/mkv files
MP4S=()
while IFS= read -r -d '' f; do
  MP4S+=("$f")
done < <(find "${RECORDING_DIR}" -type f \( -name '*.mp4' -o -name '*.mkv' \) -print0 | sort -z)

if [[ ${#MP4S[@]} -eq 0 ]]; then
  err "MP4/MKV tapılmadı: ${RECORDING_DIR}"
  exit 1
fi

ROOM_NAME="$(basename "${RECORDING_DIR}" | sed 's/[^a-zA-Z0-9._-]/_/g')"
DATE_PREFIX="$(date +%Y/%m/%d)"
OK=0

for SRC in "${MP4S[@]}"; do
  FNAME="$(basename "${SRC}")"
  REMOTE_KEY="${UPLOAD_PATH}/${DATE_PREFIX}/${ROOM_NAME}/${FNAME}"
  URL="https://${STORAGE_HOST}/${BUNNY_STORAGE_ZONE}/${REMOTE_KEY}"

  log "Upload: ${SRC} → ${URL}"
  HTTP_CODE="$(curl -sS -o /tmp/bunny-upload-resp.txt -w '%{http_code}' \
    --retry 5 --retry-delay 5 --retry-all-errors \
    -X PUT \
    -H "AccessKey: ${BUNNY_STORAGE_PASSWORD}" \
    -H "Content-Type: application/octet-stream" \
    --data-binary @"${SRC}" \
    "${URL}" || echo "000")"

  if [[ "${HTTP_CODE}" =~ ^20[01]$ ]]; then
    log "OK (${HTTP_CODE}): ${REMOTE_KEY}"
    if [[ -n "${CDN_HOST}" ]]; then
      log "CDN URL: https://${CDN_HOST}/${REMOTE_KEY}"
    fi
    # Metadata sidecar
    META="${SRC}.bunny.json"
    cat > "${META}" <<JSON
{
  "local": "${SRC}",
  "remote_key": "${REMOTE_KEY}",
  "storage_url": "${URL}",
  "cdn_url": "${CDN_HOST:+https://${CDN_HOST}/${REMOTE_KEY}}",
  "uploaded_at": "$(date -Iseconds)",
  "http_code": ${HTTP_CODE}
}
JSON
    # Upload metadata too (best-effort)
    curl -sS -X PUT \
      -H "AccessKey: ${BUNNY_STORAGE_PASSWORD}" \
      -H "Content-Type: application/json" \
      --data-binary @"${META}" \
      "https://${STORAGE_HOST}/${BUNNY_STORAGE_ZONE}/${REMOTE_KEY}.bunny.json" >/dev/null || true

    rm -f "${SRC}" "${META}"
    OK=1
  else
    err "Upload failed HTTP ${HTTP_CODE} for ${SRC}"
    cat /tmp/bunny-upload-resp.txt >&2 || true
  fi
done

if [[ "${OK}" -eq 1 ]]; then
  # Directory boşdursa sil
  if [[ -z "$(find "${RECORDING_DIR}" -type f ! -name '*.json' 2>/dev/null | head -1)" ]]; then
    log "Lokal recording silinir: ${RECORDING_DIR}"
    rm -rf "${RECORDING_DIR}"
  fi
  exit 0
fi

exit 1
