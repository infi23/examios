# Panduan Deployment AgreXambro iOS — Kiosk Mode untuk Sekolah

> **Tujuan:** Mengunci iPad/iPhone ke aplikasi AgreXambro selama ujian, mencegah siswa keluar tanpa otorisasi (analog Safe Exam Browser di Windows).

---

## Pilihan Deployment

| Metode | Biaya | Skala | Effort | Cocok untuk |
|--------|-------|-------|--------|-------------|
| **Guided Access** | Gratis | 1 device manual | Rendah | Testing personal, ujian rumahan |
| **Apple Configurator 2** | Gratis | 5–50 device | Sedang | Sekolah kecil, lab komputer |
| **Apple School Manager + MDM** | $99/tahun Developer + biaya MDM | 50–10.000 device | Tinggi | Institusi besar, deployment massal |

Pilih sesuai skala. Untuk **lab ujian 30 iPad sekolah**, **Apple Configurator 2** sudah cukup.

---

# OPSI 1: Apple Configurator 2 (Recommended untuk Sekolah)

**Prasyarat:**
- 1 MacBook (sudah ada ✅)
- Apple Configurator 2 dari Mac App Store (gratis)
- Kabel USB Lightning/USB-C ke iPad
- **iPad harus baru/sudah di-erase** (kondisi "Hello" screen) — required untuk supervise

## Step 1: Install Apple Configurator 2

```bash
open "macappstore://apps.apple.com/app/apple-configurator-2/id1037126344"
```

Atau buka Mac App Store → cari "Apple Configurator 2" → Get.

## Step 2: Erase iPad ke Factory Settings (jika belum)

Di iPad: **Settings → General → Transfer or Reset iPad → Erase All Content and Settings**

iPad akan restart dan menampilkan **"Hello"** dalam berbagai bahasa.

## Step 3: Supervise & Enroll iPad

1. Buka Apple Configurator 2 di Mac
2. Hubungkan iPad via kabel USB → iPad muncul di Configurator
3. Klik kanan iPad → **Prepare...**
4. Setup wizard:
   - **Manual configuration** (tanpa MDM external)
   - **Supervise devices**: ✅ Aktifkan
   - **Allow devices to pair with other computers**: ❌ Nonaktifkan (lebih aman)
   - **Organization**: Buat baru (contoh: "SMA AgreXambro")
   - **Setup Assistant steps**: skip semua kecuali Language & Region (mempercepat onboarding)
5. iPad akan **factory reset ulang** dan jadi supervised device
6. Tunggu 5–10 menit per iPad

## Step 4: Install App AgreXambro

### Opsi A: Install via .ipa File

1. Di Xcode: **Product → Archive** → Distribute App → **Ad Hoc** atau **Development**
2. Export `.ipa` ke folder
3. Drag `.ipa` ke window Apple Configurator → device → klik **Add → Apps**

### Opsi B: Install via App Store / TestFlight

1. Upload app ke TestFlight (butuh paid Developer account $99/tahun)
2. Di Configurator → tab Apps → tambahkan app

## Step 5: Buat Blueprint Single App Mode

**Blueprint** = template config yang bisa di-apply ke banyak iPad sekaligus.

1. Configurator → **File → New Blueprint** → beri nama "Exam-AgreXambro"
2. Pada blueprint, klik **Add → Profiles → Single App Mode**
3. Setting Single App Mode:
   - **App**: pilih AgreXambro
   - **Touch**: ✅ Enabled
   - **Device Rotation**: ✅ Enabled
   - **Volume Buttons**: ✅ Enabled (untuk audio alarm)
   - **Ringer Switch**: ❌ Disabled
   - **Sleep/Wake Button**: ❌ Disabled
   - **Auto-Lock**: ❌ Disabled (layar tetap nyala selama ujian)
   - **Mono Audio**: ❌
   - **VoiceOver**: ❌
4. Save blueprint

## Step 6: Apply Blueprint ke iPad

1. Pilih iPad di Configurator → **Apply Blueprint → Exam-AgreXambro**
2. iPad akan masuk **Single App Mode** otomatis
3. iPad **TIDAK BISA keluar** dari app AgreXambro sampai Single App Mode dimatikan

**Untuk keluar Single App Mode:**
- Hubungkan ke Mac → buka Configurator → klik iPad → **Actions → Remove Single App Mode**
- Atau via remote command jika sudah di-enroll ke MDM

---

# OPSI 2: Autonomous Single App Mode (Hybrid)

Mode ini lebih fleksibel: **app sendiri yang lock/unlock** layar (mirip `startLockTask()` Android), tapi tetap butuh device supervised.

## Step 1: Supervise iPad (sama seperti Opsi 1)

Lakukan Step 1–3 dari Apple Configurator 2 di atas.

## Step 2: Tambah Entitlement di Project AgreXambro

Edit file `ExambroiOS/ExambroiOS.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.developer.assessment.test-taking</key>
    <true/>
</dict>
</plist>
```

## Step 3: Buat Configuration Profile Allowlist

Di Apple Configurator 2:
1. **File → New Profile** → beri nama "AgreXambro-AASAM"
2. **App Lock** section → **Configure**:
   - **App Bundle ID**: `com.exambro.ios` (atau sesuai bundle ID kamu)
   - Pilih checkbox **"Enable Autonomous Single App Mode for this app"**
3. Save → push profile ke iPad (drag ke device di Configurator)

## Step 4: Implementasi di Swift Code

Update `ExamView.swift` — ganti method `enableGuidedAccess()` dengan:

```swift
private func enableKioskMode() {
    UIAccessibility.requestGuidedAccessSession(enabled: true) { [weak self] success in
        DispatchQueue.main.async {
            if success {
                self?.isGuidedAccessActive = true
                print("✅ Autonomous Single App Mode aktif")
            } else {
                self?.showWarning("Gagal aktifkan mode aman. Pastikan iPad supervised dengan profile AgreXambro-AASAM.")
            }
        }
    }
}
```

Dengan setup ini, **app bisa lock/unlock sendiri** seperti Android `startLockTask()`.

---

# OPSI 3: Apple School Manager + MDM (Enterprise Scale)

Untuk deployment > 50 device atau institusi resmi.

## Komponen:

| Tool | Fungsi | Biaya |
|------|--------|-------|
| **Apple School Manager** | Identitas sekolah resmi di Apple, manage Apple ID siswa, bulk purchase apps | Gratis |
| **MDM Server** | Push config & app remote ke ratusan device | $1–3/device/bulan |
| **Apple Developer Program** | Distribute private app ke MDM | $99/tahun |

## Rekomendasi MDM untuk Sekolah:

| MDM | Free Tier | Cocok untuk |
|-----|-----------|-------------|
| **Jamf School** | 25 device gratis | Sekolah dasar/menengah, UI sederhana |
| **Mosyle Manager** | 30 device gratis | Sekolah kecil, integrasi Apple School Manager |
| **Microsoft Intune for Education** | Bundled dengan Office 365 | Sekolah yang sudah pakai Microsoft |
| **Cisco Meraki Systems Manager** | Tidak ada free | Enterprise besar |

## Workflow umum:

1. **Daftar Apple School Manager** di https://school.apple.com (butuh DUNS number sekolah)
2. **Hubungkan ASM ke MDM** (Jamf/Mosyle/dll)
3. **Beli device melalui Apple Authorized Reseller** dengan Apple ID sekolah → auto-enroll ke MDM
4. **Upload AgreXambro.ipa** ke Apple Developer Console → Custom App distribution
5. **MDM push** config Single App Mode + app ke semua device

---

# Build & Distribute AgreXambro.ipa

Untuk distribusi via Configurator/MDM butuh file `.ipa`:

## Via Xcode UI:

1. Pilih destination → **Any iOS Device (arm64)**
2. **Product → Archive** (⌘B dengan scheme Release)
3. Setelah archive selesai, window Organizer terbuka
4. Klik **Distribute App**:
   - **Development** (untuk testing, max 100 device terdaftar di account)
   - **Ad Hoc** (sama dengan Development)
   - **App Store** (lewat App Review — public)
   - **Enterprise** (butuh Apple Developer Enterprise Program $299/tahun — distribute internal tanpa App Store)
5. Pilih signing → export `.ipa`

## Via Command Line:

```bash
cd /Users/muiskamaruddin/Documents/exambro-project/exambro-ios

# Archive
xcodebuild -project ExambroiOS.xcodeproj \
  -scheme ExambroiOS \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath ./build/ExambroiOS.xcarchive \
  archive

# Export .ipa (butuh ExportOptions.plist)
xcodebuild -exportArchive \
  -archivePath ./build/ExambroiOS.xcarchive \
  -exportPath ./build/ipa \
  -exportOptionsPlist ExportOptions.plist
```

Contoh `ExportOptions.plist`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>development</string>
    <key>teamID</key>
    <string>YOUR_TEAM_ID</string>
    <key>signingStyle</key>
    <string>automatic</string>
</dict>
</plist>
```

---

# Checklist Sebelum Ujian Live

- [ ] Semua iPad sudah supervised & terinstall AgreXambro
- [ ] Profile Single App Mode (atau AASAM) sudah diapply
- [ ] **Test 1 device dulu**: scan QR config → login → start exam → coba keluar app (harus gagal)
- [ ] **Test internet block**: aktifkan mobile hotspot → app harus lock merah otomatis
- [ ] **Test split-screen** (iPad): swipe app kedua dari Dock → app harus lock
- [ ] Server B, C, MinIO, Redis berjalan dan bisa diakses dari iPad
- [ ] **Backup plan**: siapkan 1–2 iPad cadangan kalau ada yang error

---

# Troubleshooting

| Masalah | Solusi |
|---------|--------|
| iPad tidak muncul di Configurator | Cek kabel USB, trust Mac di iPad, restart Configurator |
| "Failed to enable Single App Mode" | iPad belum supervised, ulangi Step 3 Configurator |
| AASAM tidak bekerja | Cek entitlement `assessment.test-taking`, cek profile AASAM ter-install |
| App stuck di Single App Mode setelah ujian | Connect ke Configurator → Actions → Remove Single App Mode |
| iPad lock screen muncul saat ujian | Pastikan Auto-Lock disabled di profile, atau `UIApplication.shared.isIdleTimerDisabled = true` (sudah di code) |

---

# Referensi Resmi

- **Apple Configurator 2 User Guide**: https://support.apple.com/guide/apple-configurator-2
- **Apple Platform Deployment Guide**: https://support.apple.com/guide/deployment
- **Assessment Test-Taking Entitlement**: https://developer.apple.com/documentation/bundleresources/entitlements/com_apple_developer_assessment_test-taking
- **Apple School Manager**: https://school.apple.com
- **Jamf School Free**: https://www.jamf.com/products/jamf-school/

---

> **Catatan untuk Sekolah:** Untuk 30 iPad lab ujian, **Opsi 1 (Apple Configurator 2)** adalah pilihan terbaik — gratis, satu kali setup, ujian berjalan tanpa intervensi guru selama Single App Mode aktif. Hanya butuh 1 admin untuk mengelola semua device dari 1 MacBook.
