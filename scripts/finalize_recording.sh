#!/usr/bin/env bash
# Jibri finalize_recording.sh hook
# Args: <recording_directory>
# Flow: wait for file settle → bunny-upload → delete local

set -euo pipefail

RECORDING_DIR="${1:-}"
LOG="/var/log/jitsi/recording-finalize.log"
mkdir -p "$(dirname "${LOG}")"

exec >>"${LOG}" 2>&1
echo "==== $(date -Iseconds) finalize: ${RECORDING_DIR} ===="

if [[ -z "${RECORDING_DIR}" || ! -d "${RECORDING_DIR}" ]]; then
  echo "Invalid recording dir"
  exit 1
fi

# Wait until mp4 size stabilizes (ffmpeg flush)
for i in $(seq 1 30); do
  SIZE1="$(du -sb "${RECORDING_DIR}" 2>/dev/null | awk '{print $1}')"
  sleep 2
  SIZE2="$(du -sb "${RECORDING_DIR}" 2>/dev/null | awk '{print $1}')"
  if [[ "${SIZE1}" == "${SIZE2}" ]]; then
    break
  fi
done

# Optional: strip metadata / ensure readable
chown -R jibri:jibri "${RECORDING_DIR}" 2>/dev/null || true

/opt/jitsi-jibri/bunny-upload.sh "${RECORDING_DIR}"
echo "==== done $(date -Iseconds) ===="
