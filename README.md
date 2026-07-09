# jitsi-deploy

Bir əmrlə GCP-də Jitsi Meet cluster + Jibri recording + Bunny upload.

**Default (10 paralel recording, az VM):**

```
meet-control   e2-standard-4     Nginx + Prosody + Jicofo + Coturn
meet-jvb       e2-standard-8     Video bridge
recorder-1..2  e2-standard-8     hər VM-də 5 Jibri prosesi → Bunny
```

**Adaptiv recording:** `CONCURRENT_RECORDINGS=10` → deploy özü **2 recorder VM × 5 Jibri proses** seçir.  
1 VM ≠ 1 record — eyni hostda bir neçə Jibri (`jibri@1`…`jibri@N`) işləyir. Jicofo brewery boş slotu seçir.

Canlı server (`meet.ingress.academy`) konfiqlərinə əsaslanır: 15 nəfərlik qruplar, 720p, simulcast, TURN.

---

## Tələblər (lokal maşın və ya Cloud Shell)

Yalnız bunlar lazımdır — **qalan hər şeyi `./deploy.sh` özü edir**:

- `gcloud` + `gcloud auth login` (Cloud Shell-də artıq var)
- GCP project + **billing aktiv**
- `.env` doldurulmuş

`deploy.sh` avtomatik quraşdırır: **Terraform**, **jq**, skript icazələri, API enable, App Engine (scheduler), SSH açarı, control + jvb + recorder VM-lər, multi-Jibri setup, DNS, scheduler jobs.

---

## 1 dəqiqəlik start

```bash
git clone https://github.com/Aladdin-Biyabangard/jitsi-cluster.git
cd jitsi-cluster
cp .env.example .env
nano .env          # doldurun
./deploy.sh        # hamısı buradan — başqa skript lazım deyil
```

Deploy ~20–40 dəqiqə çəkir. Sonunda:

```
URL: https://meet.yourdomain.com
meet-control IP: x.x.x.x
```

DNS A record: `DOMAIN → meet-control IP` (Cloudflare token versəniz avtomatik).

---

## `.env` — nə doldurmaq lazımdır?

| Dəyişən | Məcburi | İzah |
|---------|---------|------|
| `GCP_PROJECT_ID` | ✅ | Yeni GCP project |
| `DOMAIN` | ✅ | məs. `meet.ingress.academy` |
| `ADMIN_EMAIL` | ✅ | Let's Encrypt |
| `BUNNY_LIBRARY_ID` | ✅ recording | Stream → **Video library ID** (məs. `692053`) |
| `BUNNY_API_KEY` | ✅ recording | Stream → **API Key** (Read-only DEYİL) |
| `BUNNY_CDN_HOSTNAME` | optional | Stream → **CDN hostname** (məs. `vz-….b-cdn.net`) |
| `CLOUDFLARE_*` | | DNS avtomatik yeniləmə |
| `SCHEDULE_*` | | Default: 03:30–06:05 UTC (= 07:30–10:05 Bakı) |

### Bunny Stream — hansı sahələr lazımdır?

Ingress portal (`BUNNY_LIBRARY_ID` + `BUNNY_API_KEY`) ilə **eyni** Stream library istifadə olunur.

| Bunny dashboard sahəsi | `.env` | Lazımdır? |
|------------------------|--------|-----------|
| **Video library ID** | `BUNNY_LIBRARY_ID` | ✅ Bəli |
| **API Key** | `BUNNY_API_KEY` | ✅ Bəli |
| **CDN hostname** | `BUNNY_CDN_HOSTNAME` | optional (log/thumbnail) |
| Read-only API Key | — | ❌ Xeyr |
| Pull zone adı | — | ❌ Xeyr |

---

## Recording axını (Ingress portal ilə eyni API)

```
Meeting → Start recording (UI)
    ↓
Jibri MP4 yazır (/srv/recordings)
    ↓
Meeting bitir / Stop recording
    ↓
finalize_recording.sh
    ↓
bunny-upload.sh
    1) POST /library/{id}/videos          → video GUID
    2) PUT  /library/{id}/videos/{guid}   → MP4 binary
    ↓
HTTP 2xx  →  lokal MP4 + qovluq silinir
```

Nəticə (portal `bunny_video_id` kimi):

```
library: 692053
video:   <guid>
embed:   https://iframe.mediadelivery.net/embed/692053/<guid>
```

Log: hər Jibri-də `/var/log/jitsi/bunny-uploads.jsonl`

---

## Schedule (xərc qənaəti)

`ENABLE_SCHEDULE=true` olanda Cloud Scheduler hər VM-i start/stop edir.

| Bakı vaxtı | UTC (default) |
|------------|---------------|
| 07:30 start | 03:30 |
| 10:05 stop | 06:05 |

Manual:

```bash
GCP_PROJECT_ID=... GCP_ZONE=europe-west1-b ./scripts/schedule-all.sh start
GCP_PROJECT_ID=... GCP_ZONE=europe-west1-b ./scripts/schedule-all.sh stop
```

**IP qənaəti:** yalnız `meet-control` və `meet-jvb` statik xarici IP. Recorder VM-lər yalnız daxili IP (SSH: meet-control bastion).

---

## Arxitektura

```
                    Internet
                       │
          ┌────────────┼────────────┐
          ▼                         ▼
   meet-control                 meet-jvb
   (HTTPS/XMPP/TURN)            (UDP 10000)
          │                         │
          └──────────┬──────────────┘
                     │ VPC internal
              ┌──────┴──────┐
              ▼             ▼
        recorder-1     recorder-2
        jibri@1…@5     jibri@1…@5
              │             │
              └──────┬──────┘
                     ▼
               Bunny Stream
```

`.env`-də yalnız hədəfi yazın:

```bash
CONCURRENT_RECORDINGS=10   # eyni anda max recording
# RECORDER_COUNT=2         # optional override
# JIBRI_PER_VM=5           # optional override
```


---

## Fayl strukturu

```
jitsi-deploy/
├── deploy.sh                 # ← əsas əmr
├── destroy.sh
├── .env.example
├── config/
│   ├── meet-custom.js        # live server 15-user config
│   └── sysctl-jitsi.conf
├── scripts/
│   ├── setup-control.sh
│   ├── setup-jvb.sh
│   ├── setup-jibri.sh
│   ├── bunny-upload.sh
│   ├── finalize_recording.sh
│   ├── schedule-all.sh
│   └── install-scheduler-jobs.sh
└── terraform/
    ├── main.tf
    ├── variables.tf
    └── outputs.tf
```

---

## Yeni GCP hesabında

1. Yeni project yarat, billing bağla
2. `gcloud auth login` + `gcloud config set project NEW_ID`
3. `cp .env.example .env` — `CONCURRENT_RECORDINGS=10` (2×recorder, 28 vCPU)
4. `./deploy.sh`

### Quota limitləri (yeni hesab)

| Limit | Default | Bu deploy (default) |
|-------|---------|---------------------|
| `CPUS_ALL_REGIONS` | 32 | 4 + 8 + 2×8 = **28** |
| `IN_USE_ADDRESSES` (region) | 8 | **2** (yalnız control + jvb) |

Daha çox paralel recording üçün `CONCURRENT_RECORDINGS` artırın və ya [Quota](https://console.cloud.google.com/iam-admin/quotas) artırın.

### Yarımçıq deploy (köhnə jibri-* VM-lərdən sonra)

Cloud Shell-də:

```bash
cd ~/jitsi-cluster
git pull
nano .env   # CONCURRENT_RECORDINGS=10  (JIBRI_COUNT silin)
# Köhnə 1:1 jibri VM-ləri silmək üçün (state qarışıqlığı olarsa):
# ./destroy.sh && ./deploy.sh
gcloud services enable cloudresourcemanager.googleapis.com --project=jitsi-cluster-501917
./deploy.sh
```

Terraform `jibri-*` adlarını `recorder-*` ilə əvəz edəcək; qarışıqlıq olarsa əvvəl `./destroy.sh`.

Köhnə hesabı bağlamaq üçün:

```bash
./destroy.sh
```

---

## Troubleshooting

| Problem | Həll |
|---------|------|
| `CPUS_ALL_REGIONS` exceeded | `.env`: `JIBRI_MACHINE_TYPE=e2-standard-8`, `RECORDER_COUNT=2` və ya quota artır |
| `IN_USE_ADDRESSES` exceeded | Recorder-lər xarici IP almır; `git pull` + yenidən deploy |
| Cloud Resource Manager API disabled | `gcloud services enable cloudresourcemanager.googleapis.com` |
| SSL uğursuz | DNS yayımlandıqdan sonra LE skriptini yenidən işlət |
| Recording düyməsi yoxdur | brewery — `journalctl -u 'jibri@*' -n 50` |
| JVB qoşulmur | Control Prosody 5222 + firewall `jitsi-allow-internal` |
| Bunny upload fail | `/var/log/jitsi/recording-finalize.log` və `bunny.env` |
| Recorder setup log | `secrets/setup-recorder-*.log` |

---

## Təxmini xərc (schedule ilə ~2.5 saat/gün)

| | Təxmini |
|---|---------|
| Compute (4 VM, schedule) | ~$70/ay |
| Disk (~260 GB) | ~$40/ay |
| 2× static IP (stop vaxtı) | ~$7/ay |
| **Cəmi** | **~$120–160/ay** |

24/7 işləsə ~$1,600+/ay olardı.
