# APK Distribution Setup

> Panduan operasional untuk distribusi APK self-hosted offline-first.
> Skenario target: 500-1000 device tablet siswa di LAN sekolah.

## Arsitektur

```
Android device ──► Server B (/api/v1/app/latest-apk) ──► metadata
                                                          │
              ◄── { url, version, sha256 } ◄──────────────┘
              │
              └────► MinIO bucket "exambro-apk" ──► APK file
                     (anonymous read public)
```

## 1. Setup MinIO bucket publik (sekali saja)

### Cara A — Via MinIO Console (web UI)

1. Login ke `https://minio.agrexambro.my.id` (atau alamat MinIO LAN Anda).
2. **Create Bucket** → nama `exambro-apk`.
3. Klik bucket → tab **Access** → **Anonymous** → **Add Access Rule**:
   - Prefix: `/`
   - Access: **readonly**
4. Save.

### Cara B — Via `mc` CLI

```bash
# Install mc (MinIO Client) di VPS:
wget https://dl.min.io/client/mc/release/linux-amd64/mc
chmod +x mc && sudo mv mc /usr/local/bin/

# Konfigurasi alias
mc alias set exambro https://s3.agrexambro.my.id <ACCESS_KEY> <SECRET_KEY>

# Buat bucket
mc mb exambro/exambro-apk

# Set anonymous read policy
mc anonymous set download exambro/exambro-apk
```

### Verifikasi
```bash
# File apa pun yang diupload harus bisa diakses tanpa auth:
curl -I https://s3.agrexambro.my.id/exambro-apk/test.txt
# → HTTP 200 atau 404 (bukan 403)
```

## 2. Workflow rilis APK baru

### Step 1 — Build APK release di laptop

```powershell
cd E:\exambro2026\android-client

# Naikkan versionName di build.gradle.kts dulu, misal "1.1.0"
# (pastikan signing config sudah disiapkan untuk release)
.\gradlew assembleRelease

# APK output:
# app/build/outputs/apk/release/app-release.apk
```

### Step 2 — Hitung SHA-256 (opsional, untuk integrity check)

```powershell
Get-FileHash -Algorithm SHA256 "app\build\outputs\apk\release\app-release.apk" | Select-Object -ExpandProperty Hash
```

Output, contoh: `A3F2B7E9...` (64 karakter hex)

### Step 3 — Upload ke MinIO bucket

```bash
# Pakai mc:
mc cp app-release.apk exambro/exambro-apk/exambro-1.1.0.apk

# Atau via web UI (drag-drop di MinIO Console).
```

### Step 4 — Update `app_config` di Server B

```sql
UPDATE app_config SET value = 'https://s3.agrexambro.my.id/exambro-apk/exambro-1.1.0.apk'
    WHERE key = 'latest_apk_url';
UPDATE app_config SET value = '1.1.0'
    WHERE key = 'latest_apk_version';
UPDATE app_config SET value = '<ukuran-bytes>'
    WHERE key = 'latest_apk_size_bytes';
UPDATE app_config SET value = '<sha256-hex>'
    WHERE key = 'latest_apk_sha256';

-- Wajibkan device update ke versi baru:
UPDATE app_config SET value = '1.1.0'
    WHERE key = 'min_supported_android_version';
```

Dalam **60 detik** (cache TTL), semua device dengan versi lama akan:
1. Detect outdated → UpdateRequiredActivity muncul
2. Tombol "Download & Install" (offline) atau "Perbarui Sekarang" (online)
3. Offline: download APK, verifikasi SHA-256, trigger PackageInstaller
4. User klik "Install" di dialog Android → versi baru terpasang

## 3. Test integrasi

### Lokal (laptop)
```powershell
# Pastikan app_config sudah ada nilai dummy:
$env:PGPASSWORD = "exambro_secret"
& "C:\laragon\bin\postgresql\postgresql-17.5-2-windows-x64-binaries\bin\psql.exe" `
    -h localhost -U exambro -d exambro_security -c `
    "UPDATE app_config SET value='http://localhost:9000/exambro-apk/test.apk' WHERE key='latest_apk_url';"
& "C:\laragon\bin\postgresql\postgresql-17.5-2-windows-x64-binaries\bin\psql.exe" `
    -h localhost -U exambro -d exambro_security -c `
    "UPDATE app_config SET value='1.1.0' WHERE key='latest_apk_version';"

# Test endpoint
curl.exe -i "http://localhost:8081/api/v1/app/latest-apk"
# → HTTP 200 + JSON { url, version, size_bytes, sha256 }
```

### VPS
```bash
sudo docker compose exec postgresql psql -U exambro -d exambro_security -c "
    UPDATE app_config SET value = 'https://s3.agrexambro.my.id/exambro-apk/exambro-1.1.0.apk'
        WHERE key='latest_apk_url';
    UPDATE app_config SET value='1.1.0' WHERE key='latest_apk_version';
"

curl -ki 'https://api.agrexambro.my.id/api/v1/app/latest-apk'
# → HTTP 200 + JSON metadata
```

## 4. Pertimbangan operasional

### Bandwidth (penting di skala 500-1000 device)

- **APK ukuran ~30 MB** × 500 device = ~15 GB total transfer per rilis.
- **LAN sekolah** (1 Gbps switch): ~120 detik teori, realistis 10-30 menit kalau bersamaan.
- **VPS internet**: cek kuota bandwidth provider Anda. Hetzner CX22 = 20 TB/bulan = aman.
- **Rate limit nginx** kalau perlu, di `nginx/custom.conf`:
  ```
  limit_req_zone $binary_remote_addr zone=apk:10m rate=2r/m;
  location /exambro-apk/ {
      limit_req zone=apk burst=5 nodelay;
  }
  ```

### Caching device tidak terdownload ulang

Server B endpoint return `Cache-Control: public, max-age=60` (kode kita).
File APK di MinIO biasanya tidak punya Cache-Control header.
Tambah header di nginx kalau perlu:
```
location /exambro-apk/ {
    expires 7d;
    add_header Cache-Control "public, immutable";
}
```

### Rollback rilis

Kalau APK 1.1.0 ternyata buggy:
```sql
UPDATE app_config SET value='1.0.0' WHERE key='min_supported_android_version';
```
Device yang sudah di-update ke 1.1.0 tidak otomatis downgrade — mereka harus install APK 1.0.0 manual atau Anda push hotfix 1.1.1.

### Verifikasi SHA-256

Kode Android melakukan validasi otomatis. Kalau mismatch → file dihapus,
user dapat error "checksum tidak cocok", retry tersedia. Mencegah:
- File corrupt saat transfer
- Man-in-the-middle attack (terutama di mode HTTP LAN)

Kalau Anda **tidak** isi `latest_apk_sha256`, validasi di-skip (tetap aman karena
HTTPS+CA chain di mode online, atau LAN trusted di mode offline).
