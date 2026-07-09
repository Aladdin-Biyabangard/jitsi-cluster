# jitsi-deploy

Bir əmrlə GCP-də **11 VM** Jitsi Meet cluster + Jibri recording + Bunny upload.

```
meet-control   e2-standard-4     Nginx + Prosody + Jicofo + Coturn
meet-jvb       e2-standard-16    Video bridge (9 qrup)
jibri-1..9     e2-standard-4     Recording → Bunny → lokal sil
```

Canlı server (`meet.ingress.academy`) konfiqlərinə əsaslanır: 15 nəfərlik qruplar, 720p, simulcast, TURN.

---

## Tələblər (lokal maşın)

- [gcloud CLI](https://cloud.google.com/sdk/docs/install) + `gcloud auth login`
- [Terraform](https://developer.hashicorp.com/terraform/install) ≥ 1.5
- `jq`, `ssh`, `scp`, `curl`
- GCP project (billing aktiv)
- Domain DNS (Cloudflare optional)
- Bunny Storage Zone + Access Key

---

## 1 dəqiqəlik start

```bash
git clone <bu-repo>
cd jitsi-deploy
cp .env.example .env
nano .env          # doldurun
./deploy.sh
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
| `BUNNY_STORAGE_ZONE` | ✅ | Bunny storage zone adı |
| `BUNNY_STORAGE_PASSWORD` | ✅ | Storage AccessKey |
| `BUNNY_STORAGE_REGION` | | `de`, `ny`, `sg`… |
| `BUNNY_CDN_HOSTNAME` | | məs. `xxx.b-cdn.net` |
| `CLOUDFLARE_*` | | DNS avtomatik yeniləmə |
| `SCHEDULE_*` | | Default: 03:30–06:05 UTC (= 07:30–10:05 Bakı) |

---

## Recording axını

```
Meeting → Start recording (UI)
    ↓
Jibri MP4 yazır (/srv/recordings)
    ↓
Meeting bitir / Stop recording
    ↓
finalize_recording.sh
    ↓
bunny-upload.sh  →  Bunny Storage PUT
    ↓
HTTP 200/201  →  lokal MP4 + qovluq silinir
```

Bunny path nümunəsi:

```
recordings/2026/07/09/room-name/recording.mp4
```

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

**IP qənaəti:** yalnız `meet-control` və `meet-jvb` statik IP saxlayır. Jibri-lər ephemeral IP istifadə edir (stop olanda IP ödənişi yoxdur).

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
        ┌────────────┼────────────┐
        ▼            ▼            ▼
     jibri-1      jibri-2  …   jibri-9
        │
        └──► Bunny Storage ──► CDN
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
3. `.env`-də yalnız `GCP_PROJECT_ID` dəyiş
4. `./deploy.sh`

Köhnə hesabı bağlamaq üçün:

```bash
./destroy.sh
```

---

## Troubleshooting

| Problem | Həll |
|---------|------|
| SSL uğursuz | DNS yayımlandıqdan sonra LE skriptini yenidən işlət (deploy sonunda göstərilir) |
| Recording düyməsi yoxdur | `config.fileRecordingsEnabled` + Jibri brewery — jibri log: `journalctl -u jibri -n 50` |
| JVB qoşulmur | Control Prosody 5222 + firewall `jitsi-allow-internal` |
| Bunny upload fail | `/var/log/jitsi/recording-finalize.log` və `bunny.env` AccessKey |
| Jibri setup log | `secrets/setup-jibri-*.log` |

---

## Təxmini xərc (schedule ilə ~2.5 saat/gün)

| | Təxmini |
|---|---------|
| Compute | ~$140/ay |
| Disk (~370 GB) | ~$60/ay |
| 2× static IP (stop vaxtı) | ~$7/ay |
| **Cəmi** | **~$200–280/ay** |

24/7 işləsə ~$1,600+/ay olardı.
