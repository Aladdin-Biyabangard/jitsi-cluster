#!/usr/bin/env bash
# jibri-N: Chrome + FFmpeg recording → Bunny upload → delete

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"
require_root

DOMAIN="${DOMAIN:?}"
CONTROL_PRIVATE_IP="${CONTROL_PRIVATE_IP:?}"
JIBRI_RECORDER_PASS="${JIBRI_RECORDER_PASS:?}"
JIBRI_XMPP_PASS="${JIBRI_XMPP_PASS:?}"
JIBRI_NICKNAME="${JIBRI_NICKNAME:-jibri-$(hostname)}"
BUNNY_LIBRARY_ID="${BUNNY_LIBRARY_ID:-}"
BUNNY_API_KEY="${BUNNY_API_KEY:-}"
BUNNY_CDN_HOSTNAME="${BUNNY_CDN_HOSTNAME:-}"

log "Jibri setup: nick=${JIBRI_NICKNAME} control=${CONTROL_PRIVATE_IP}"

install_base
add_jitsi_repo
apply_sysctl "${SCRIPT_DIR}/../config/sysctl-jitsi.conf"

hostnamectl set-hostname "${JIBRI_NICKNAME}.${DOMAIN}"
grep -q "${DOMAIN}" /etc/hosts || echo "${CONTROL_PRIVATE_IP} ${DOMAIN}" >> /etc/hosts
grep -q "auth.${DOMAIN}" /etc/hosts || echo "${CONTROL_PRIVATE_IP} auth.${DOMAIN}" >> /etc/hosts
grep -q "recorder.${DOMAIN}" /etc/hosts || echo "${CONTROL_PRIVATE_IP} recorder.${DOMAIN}" >> /etc/hosts

# ALSA loopback for Jibri audio
if ! grep -q snd-aloop /etc/modules; then
  echo "snd-aloop" >> /etc/modules
fi
modprobe snd-aloop || true

# Google Chrome (Jibri dependency)
if ! command -v google-chrome-stable >/dev/null 2>&1; then
  log "Google Chrome quraşdırılır..."
  curl -fsSL https://dl.google.com/linux/linux_signing_key.pub \
    | gpg --dearmor -o /usr/share/keyrings/google-chrome.gpg
  echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome.gpg] http://dl.google.com/linux/chrome/deb/ stable main" \
    > /etc/apt/sources.list.d/google-chrome.list
  apt-get update -qq
  apt-get install -y google-chrome-stable
fi

wait_apt
apt-get install -y jibri

# Recording directory
mkdir -p /srv/recordings
chown jibri:jibri /srv/recordings

# Bunny env + scripts
mkdir -p /opt/jitsi-jibri
cat > /opt/jitsi-jibri/bunny.env <<ENV
BUNNY_LIBRARY_ID=${BUNNY_LIBRARY_ID}
BUNNY_API_KEY=${BUNNY_API_KEY}
BUNNY_CDN_HOSTNAME=${BUNNY_CDN_HOSTNAME}
ENV
chmod 600 /opt/jitsi-jibri/bunny.env
chown jibri:jibri /opt/jitsi-jibri/bunny.env

cp "${SCRIPT_DIR}/bunny-upload.sh" /opt/jitsi-jibri/bunny-upload.sh
cp "${SCRIPT_DIR}/finalize_recording.sh" /opt/jitsi-jibri/finalize_recording.sh
chmod 755 /opt/jitsi-jibri/bunny-upload.sh /opt/jitsi-jibri/finalize_recording.sh
chown jibri:jibri /opt/jitsi-jibri/*.sh

# jq lazımdır (bunny-upload.sh create video response parse edir)
apt-get install -y -qq jq >/dev/null 2>&1 || true

# Jibri config
cat > /etc/jitsi/jibri/jibri.conf <<JIBRI
jibri {
  id = "${JIBRI_NICKNAME}"
  single-use-mode = false

  recording {
    recordings-directory = "/srv/recordings"
    finalize-script = "/opt/jitsi-jibri/finalize_recording.sh"
  }

  api {
    xmpp {
      environments = [
        {
          name = "prod"
          xmpp-server-hosts = [ "${CONTROL_PRIVATE_IP}" ]
          xmpp-domain = "${DOMAIN}"

          control-muc {
            domain = "internal.auth.${DOMAIN}"
            room-name = "JibriBrewery"
            nickname = "${JIBRI_NICKNAME}"
          }

          control-login {
            domain = "auth.${DOMAIN}"
            username = "jibri"
            password = "${JIBRI_XMPP_PASS}"
          }

          call-login {
            domain = "recorder.${DOMAIN}"
            username = "recorder"
            password = "${JIBRI_RECORDER_PASS}"
          }

          strip-from-room-domain = "conference."
          usage-timeout = 0
          trust-all-xmpp-certs = true
        }
      ]
    }
  }

  chrome {
    flags = [
      "--use-fake-ui-for-media-stream",
      "--start-maximized",
      "--kiosk",
      "--enabled",
      "--disable-infobars",
      "--autoplay-policy=no-user-gesture-required",
      "--ignore-certificate-errors"
    ]
  }

  ffmpeg {
    resolution = "1280x720"
    // audio-source = "alsa"
    // audio-device = "plug:bsnoop"
  }
}
JIBRI

# Prosody brewery room is created by jicofo; ensure jibri user can join via control setup

ufw_base
ufw allow from 10.0.0.0/8
ufw --force enable

usermod -aG adm,audio,video,plugdev jibri 2>/dev/null || true

systemctl enable jibri
systemctl restart jibri

sleep 3
if systemctl is-active --quiet jibri; then
  log "Jibri aktiv: ${JIBRI_NICKNAME}"
else
  warn "Jibri start olmadı — journalctl -u jibri -n 50"
  journalctl -u jibri --no-pager -n 30 || true
fi
