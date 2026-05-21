# Rencana Implementasi Force-Update (Wajib Versi Terbaru)

> **Dokumen panduan untuk agen AI.**
> Tujuan: mewajibkan aplikasi AgreXambro (iOS & Android) selalu memakai versi
> terbaru — versi lama otomatis terblokir dan diarahkan untuk update.
>
> Pekerjaan terbagi 3 host terpisah:
> - **BAGIAN A — Server B** (Go/Gin) — host/VPS terpisah.
> - **BAGIAN B — Aplikasi iOS** (Swift) — repo `exambro-ios` di Mac.
> - **BAGIAN C — Aplikasi Android** (Kotlin) — repo `android-client`.
>
> Ketiga bagian harus konsisten pada kontrak API yang dijelaskan di bawah.

---

## 0. Prinsip & Konteks

1. **Force-update hanya bekerja jika mekanismenya sudah ada di versi yang dipaksa.**
   Maka mekanisme ini WAJIB masuk ke iOS v1.0.0 dan Android v1.0.0
   SEBELUM rilis pertama ke App Store / Play Store / distribusi APK.
   **Versi tanpa mekanisme ini akan jadi "abadi" — tidak bisa di-deprecate.**
2. **Server adalah sumber kebenaran.** Untuk memblokir versi lama cukup
   `UPDATE app_config SET value = '...' WHERE key = 'min_supported_<platform>_version'`
   — tanpa redeploy server, tanpa update/submit ulang app.
3. **Fail-open:** jika server tidak terjangkau, app TIDAK diblokir
   (mencegah app mati total saat server down). Ini keputusan desain.
4. **Format versi semver `x.y.z`** wajib konsisten di kedua sisi.
5. App iOS sudah punya `ConfigManager.securityApiUrl` sebagai base URL Server B.
   Android client harus ekspos field setara dari config dekripsi QR.

### Versioning Policy

- Setiap rilis yang fix **kritikal security/anti-cheat** → naikkan
  `min_supported_<platform>_version` ke versi rilis tersebut segera setelah rilis tersedia di store.
- Rilis fitur biasa → tidak perlu naikkan minimum (cukup soft notification).
- Grace period: beri ≥ 48 jam antara rilis tersedia di store dan menaikkan minimum,
  agar user punya waktu update (App Store / Play Store butuh waktu propagasi).

---

## KONTRAK API (acuan ketiga bagian)

### Endpoint

```
GET {securityApiUrl}/api/v1/app/version-check?platform=<ios|android>&version=<x.y.z>
```

Response header **wajib**:
```
Cache-Control: public, max-age=60
```

### Response — versi MASIH didukung

```
HTTP 200
{ "status": "ok" }
```

### Response — versi USANG

```
HTTP 426 Upgrade Required
{
  "error": "APP_OUTDATED",
  "min_version": "1.2.0",
  "force": true,
  "message": "Versi aplikasi terlalu lama. Wajib perbarui untuk melanjutkan."
}
```

- `force: true`  → hard block (layar wajib update, tidak bisa dilewati).
- `force: false` → soft (boleh lanjut; app cukup menampilkan banner — opsional).

### Response — platform tidak dikenal

```
HTTP 200
{ "status": "ok" }
```
(fail-open — jangan blokir client dengan platform string aneh)

---

# BAGIAN A — SERVER B (Go/Gin) — Host Terpisah

> Modul: `github.com/exambro/server-b-security`.
> Struktur: `cmd/server/main.go`, `internal/handler/`, `internal/service/`,
> `internal/repository/`, `migrations/`.

## A.1. Migration BARU: `migrations/005_app_config.sql`

```sql
-- Tabel konfigurasi runtime untuk Server B.
-- Diubah lewat SQL/dashboard tanpa redeploy.
CREATE TABLE IF NOT EXISTS app_config (
    key        VARCHAR(64)  PRIMARY KEY,
    value      VARCHAR(255) NOT NULL,
    updated_at TIMESTAMP    DEFAULT NOW()
);

-- Seed nilai awal. Naikkan via UPDATE saat ingin memblokir versi lama.
INSERT INTO app_config (key, value) VALUES
    ('min_supported_ios_version',     '1.0.0'),
    ('force_update_ios',              'true'),
    ('min_supported_android_version', '1.0.0'),
    ('force_update_android',          'true')
ON CONFLICT (key) DO NOTHING;
```

## A.2. File BARU: `internal/repository/app_config_repository.go`

```go
package repository

import (
    "database/sql"
    "sync"
    "time"
)

type AppConfigRepo struct {
    db     *sql.DB
    cache  map[string]string
    expiry time.Time
    mu     sync.RWMutex
}

func NewAppConfigRepo(db *sql.DB) *AppConfigRepo {
    return &AppConfigRepo{db: db, cache: map[string]string{}}
}

// Get mengambil nilai dari cache (TTL 60 detik) atau DB.
func (r *AppConfigRepo) Get(key string) (string, error) {
    r.mu.RLock()
    if time.Now().Before(r.expiry) {
        if v, ok := r.cache[key]; ok {
            r.mu.RUnlock()
            return v, nil
        }
    }
    r.mu.RUnlock()

    return r.refresh(key)
}

func (r *AppConfigRepo) refresh(key string) (string, error) {
    r.mu.Lock()
    defer r.mu.Unlock()

    rows, err := r.db.Query(`SELECT key, value FROM app_config`)
    if err != nil {
        return "", err
    }
    defer rows.Close()

    fresh := map[string]string{}
    for rows.Next() {
        var k, v string
        if err := rows.Scan(&k, &v); err != nil {
            return "", err
        }
        fresh[k] = v
    }
    r.cache = fresh
    r.expiry = time.Now().Add(60 * time.Second)
    return fresh[key], nil
}
```

## A.3. File BARU: `internal/service/version_service.go`

```go
package service

import (
    "log"
    "strconv"
    "strings"

    "github.com/exambro/server-b-security/internal/repository"
)

type VersionService struct {
    cfg *repository.AppConfigRepo
}

func NewVersionService(cfg *repository.AppConfigRepo) *VersionService {
    return &VersionService{cfg: cfg}
}

// compareVersion: -1 jika a<b, 0 sama, 1 jika a>b. Format "x.y.z".
// Segmen yang hilang dianggap 0 ("1.0" == "1.0.0").
func compareVersion(a, b string) int {
    pa, pb := strings.Split(a, "."), strings.Split(b, ".")
    n := len(pa)
    if len(pb) > n {
        n = len(pb)
    }
    for i := 0; i < n; i++ {
        na, nb := 0, 0
        if i < len(pa) {
            na, _ = strconv.Atoi(pa[i])
        }
        if i < len(pb) {
            nb, _ = strconv.Atoi(pb[i])
        }
        if na != nb {
            if na < nb {
                return -1
            }
            return 1
        }
    }
    return 0
}

// CheckResult: hasil pengecekan versi untuk satu platform.
type CheckResult struct {
    Outdated   bool
    MinVersion string
    Force      bool
}

// Check: cek versi app terhadap konfigurasi DB.
// Fail-open: jika config gagal dibaca, anggap masih didukung.
func (s *VersionService) Check(platform, appVersion string) CheckResult {
    if appVersion == "" {
        return CheckResult{}
    }
    var minKey, forceKey string
    switch platform {
    case "ios":
        minKey, forceKey = "min_supported_ios_version", "force_update_ios"
    case "android":
        minKey, forceKey = "min_supported_android_version", "force_update_android"
    default:
        return CheckResult{} // platform tak dikenal → jangan blokir
    }

    minVer, err := s.cfg.Get(minKey)
    if err != nil || minVer == "" {
        log.Printf("VersionService: gagal baca %s: %v (fail-open)", minKey, err)
        return CheckResult{}
    }
    force, _ := s.cfg.Get(forceKey)

    return CheckResult{
        Outdated:   compareVersion(appVersion, minVer) < 0,
        MinVersion: minVer,
        Force:      force == "true",
    }
}
```

## A.4. Tambahan di `internal/handler/handler.go`

```go
// VersionCheckHandler — GET /api/v1/app/version-check
type VersionCheckHandler struct {
    svc *service.VersionService
}

func NewVersionCheckHandler(svc *service.VersionService) *VersionCheckHandler {
    return &VersionCheckHandler{svc: svc}
}

func (h *VersionCheckHandler) Check(c *gin.Context) {
    c.Header("Cache-Control", "public, max-age=60")

    platform := c.Query("platform")
    version := c.Query("version")

    res := h.svc.Check(platform, version)
    if res.Outdated {
        c.JSON(http.StatusUpgradeRequired, gin.H{ // HTTP 426
            "error":       "APP_OUTDATED",
            "min_version": res.MinVersion,
            "force":       res.Force,
            "message":     "Versi aplikasi terlalu lama. Wajib perbarui untuk melanjutkan.",
        })
        return
    }
    c.JSON(http.StatusOK, gin.H{"status": "ok"})
}
```

## A.5. Wiring di `cmd/server/main.go`

```go
// Setelah inisialisasi db pool:
appConfigRepo := repository.NewAppConfigRepo(db)
versionSvc := service.NewVersionService(appConfigRepo)
versionHandler := handler.NewVersionCheckHandler(versionSvc)

// Dalam grup route /api/v1:
api.GET("/app/version-check", versionHandler.Check)
```

## A.6. (Opsional) Gate di Start Session

Agar versi usang juga ditolak saat mulai ujian, di handler `Start`:

```go
appVersion := c.GetHeader("X-App-Version")
platform := c.GetHeader("X-App-Platform") // "ios" atau "android"
if res := h.versionSvc.Check(platform, appVersion); res.Outdated && res.Force {
    c.JSON(http.StatusUpgradeRequired, gin.H{"error": "APP_OUTDATED", ...})
    return
}
```

Header `X-App-Version` & `X-App-Platform` dikirim app pada **setiap** request
sensitif (start session, screenshot upload, event submit). Lihat B.6 & C.6.

## A.7. Verifikasi Server

```bash
go build ./...

# Migration baru
docker compose exec -T postgresql psql -U exambro -d exambro_security \
    < server-b-security/migrations/005_app_config.sql

# Smoke test endpoint
curl -i "http://localhost:8081/api/v1/app/version-check?platform=ios&version=0.9.0"
#   → HTTP 426 + body APP_OUTDATED
curl -i "http://localhost:8081/api/v1/app/version-check?platform=ios&version=1.0.0"
#   → HTTP 200 { "status": "ok" }
curl -i "http://localhost:8081/api/v1/app/version-check?platform=android&version=0.9.0"
#   → HTTP 426
curl -i "http://localhost:8081/api/v1/app/version-check?platform=unknown&version=0.1"
#   → HTTP 200 (platform aneh = fail-open)

# Test perubahan runtime tanpa redeploy
docker compose exec postgresql psql -U exambro -d exambro_security \
    -c "UPDATE app_config SET value='1.2.0' WHERE key='min_supported_ios_version';"
# Tunggu max 60 detik (cache TTL), lalu:
curl -i "http://localhost:8081/api/v1/app/version-check?platform=ios&version=1.1.0"
#   → HTTP 426 (sekarang 1.1.0 di-deprecate)
```

## A.8. Cara Memakai (Operasional)

Memblokir semua iOS < 1.2.0 di produksi:
```sql
UPDATE app_config SET value = '1.2.0' WHERE key = 'min_supported_ios_version';
```
Efek aktif maksimal 60 detik (TTL cache). **Tanpa rebuild, tanpa restart.**

---

# BAGIAN B — APLIKASI iOS (Swift)

> Repo: `exambro-ios`. SwiftUI, deployment target iOS 16.0.
> Setelah ubah file, regenerate project: `xcodegen generate` lalu re-set Team.

## B.0. Sinkronisasi Versi (WAJIB sebelum mulai)

Edit `project.yml`:
```yaml
settings:
    base:
        MARKETING_VERSION: "1.0.0"     # ubah dari "1.0" → "1.0.0" (3 segmen)
        APP_STORE_ID: "0000000000"     # ganti setelah dapat dari App Store Connect
```

Pastikan `Info.plist` ada entry:
```xml
<key>AppStoreID</key>
<string>$(APP_STORE_ID)</string>
```

## B.1. Tambahan di `ExambroiOS/Network/Models/Models.swift`

```swift
struct VersionCheckResponse: Decodable {
    let error: String?
    let minVersion: String?
    let force: Bool?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case error
        case minVersion = "min_version"
        case force, message
    }
}
```

## B.2. Tambahan method di `ExambroiOS/Network/APIClient.swift`

```swift
enum VersionCheckResult {
    case ok
    case outdated(message: String, force: Bool)
}

func checkAppVersion() async -> VersionCheckResult {
    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    guard var comps = URLComponents(string: "\(baseURL)/api/v1/app/version-check") else { return .ok }
    comps.queryItems = [
        URLQueryItem(name: "platform", value: "ios"),
        URLQueryItem(name: "version", value: version)
    ]
    guard let url = comps.url else { return .ok }
    do {
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse else { return .ok }
        if http.statusCode == 426 {
            let body = try? decoder.decode(VersionCheckResponse.self, from: data)
            return .outdated(
                message: body?.message ?? "Versi aplikasi terlalu lama. Perbarui untuk melanjutkan.",
                force: body?.force ?? true
            )
        }
        return .ok
    } catch {
        // Log untuk diagnosis (tidak blokir user).
        #if DEBUG
        print("⚠ checkAppVersion gagal: \(error.localizedDescription)")
        #endif
        return .ok
    }
}
```

## B.3. File BARU: `ExambroiOS/Views/UpdateRequiredView.swift`

```swift
import SwiftUI
import UIKit

struct UpdateRequiredView: View {
    let message: String

    private var appStoreID: String {
        Bundle.main.infoDictionary?["AppStoreID"] as? String ?? ""
    }

    var body: some View {
        ZStack {
            Color(hex: "#0f172a").ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 70))
                    .foregroundColor(Color(hex: "#fbbf24"))
                Text("Pembaruan Diperlukan")
                    .font(.title2).fontWeight(.bold)
                    .foregroundColor(.white)
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(Color(hex: "#94a3b8"))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Button(action: openAppStore) {
                    Text("Perbarui Sekarang")
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity).padding()
                        .background(Color(hex: "#fbbf24"))
                        .foregroundColor(.black).cornerRadius(12)
                }
                .padding(.horizontal, 32)
                .disabled(appStoreID.isEmpty || appStoreID == "0000000000")
            }
        }
    }

    private func openAppStore() {
        guard !appStoreID.isEmpty, appStoreID != "0000000000",
              let url = URL(string: "itms-apps://apps.apple.com/app/id\(appStoreID)") else { return }
        UIApplication.shared.open(url)
    }
}
```

> `Color(hex:)` sudah didefinisikan di `LoginView.swift` (extension Color).

## B.4. Integrasi di `ExambroiOS/Views/Login/LoginView.swift`

Tambahkan ke struct `LoginView`:
```swift
@State private var updateRequired = false
@State private var updateMessage = ""
@State private var versionCheckDone = false   // cegah re-run
```

Pada `NavigationStack { ... }`, tambahkan:
```swift
.task {
    guard !versionCheckDone else { return }
    versionCheckDone = true
    if case .outdated(let msg, let force) = await APIClient.shared.checkAppVersion(), force {
        updateMessage = msg
        updateRequired = true
    }
}
.fullScreenCover(isPresented: $updateRequired) {
    UpdateRequiredView(message: updateMessage)
}
```

> Flag `versionCheckDone` mencegah query ulang ketika user navigasi balik
> ke LoginView (`.task` re-fire setiap view appear).

## B.5. (Opsional, untuk A.6) Kirim Versi pada Request Sensitif

Tambahkan di setiap `URLRequest` builder di `APIClient`:
```swift
let ver = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
req.setValue(ver, forHTTPHeaderField: "X-App-Version")
req.setValue("ios", forHTTPHeaderField: "X-App-Platform")
```

## B.6. Regenerate & Build

```bash
cd exambro-ios
xcodegen generate
# Set Team di Xcode → Signing & Capabilities
xcodebuild -project ExambroiOS.xcodeproj -scheme ExambroiOS \
  -destination 'generic/platform=iOS Simulator,name=iPhone 16' \
  -configuration Debug CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO build
```

---

# BAGIAN C — APLIKASI ANDROID (Kotlin)

> Repo: `android-client`. Asumsi: Kotlin + (Jetpack Compose atau XML Views),
> Gradle. Package: `com.exambro.client` (sesuaikan).

## C.0. Sinkronisasi Versi (WAJIB sebelum mulai)

Edit `app/build.gradle.kts` (atau `build.gradle`):
```kotlin
android {
    defaultConfig {
        versionCode = 1
        versionName = "1.0.0"          // 3 segmen, samakan dengan iOS
        buildConfigField("String", "PLAY_STORE_PACKAGE", "\"com.exambro.client\"")
    }
}
```

Mode distribusi Android lebih variatif dari iOS:
- **Play Store** → deep link `market://details?id=<package>` atau
  fallback `https://play.google.com/store/apps/details?id=<package>`.
- **APK sideload (sekolah, offline mode)** → server harus host `latest.apk`
  + endpoint metadata. Lihat C.5 catatan.

## C.1. Tambahan di model data (mis. `data/model/VersionCheckResponse.kt`)

```kotlin
package com.exambro.client.data.model

import com.google.gson.annotations.SerializedName

data class VersionCheckResponse(
    val error: String? = null,
    @SerializedName("min_version") val minVersion: String? = null,
    val force: Boolean? = null,
    val message: String? = null
)
```

## C.2. Tambahan method di API client (mis. `data/remote/ApiClient.kt`)

Sesuaikan dengan library HTTP yang Anda pakai (Retrofit / OkHttp / Ktor).
Contoh dengan OkHttp + Gson:

```kotlin
sealed class VersionCheckResult {
    object Ok : VersionCheckResult()
    data class Outdated(val message: String, val force: Boolean) : VersionCheckResult()
}

suspend fun checkAppVersion(): VersionCheckResult = withContext(Dispatchers.IO) {
    val version = BuildConfig.VERSION_NAME
    val url = "$baseUrl/api/v1/app/version-check".toHttpUrl()
        .newBuilder()
        .addQueryParameter("platform", "android")
        .addQueryParameter("version", version)
        .build()
    val req = Request.Builder().url(url).get().build()
    try {
        client.newCall(req).execute().use { res ->
            when (res.code) {
                426 -> {
                    val body = gson.fromJson(res.body?.string(), VersionCheckResponse::class.java)
                    VersionCheckResult.Outdated(
                        message = body?.message ?: "Versi aplikasi terlalu lama. Perbarui untuk melanjutkan.",
                        force = body?.force ?: true
                    )
                }
                else -> VersionCheckResult.Ok
            }
        }
    } catch (e: Exception) {
        if (BuildConfig.DEBUG) Log.w("VersionCheck", "Gagal: ${e.message}")
        VersionCheckResult.Ok    // fail-open
    }
}
```

## C.3. File BARU: `ui/UpdateRequiredActivity.kt` (atau Composable)

Contoh dengan Activity tradisional:

```kotlin
package com.exambro.client.ui

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity
import com.exambro.client.BuildConfig
import com.exambro.client.databinding.ActivityUpdateRequiredBinding

class UpdateRequiredActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val binding = ActivityUpdateRequiredBinding.inflate(layoutInflater)
        setContentView(binding.root)

        val message = intent.getStringExtra(EXTRA_MESSAGE) ?: ""
        binding.tvMessage.text = message
        binding.btnUpdate.setOnClickListener { openStore() }

        // Cegah user keluar via tombol back (hard block).
        onBackPressedDispatcher.addCallback(this) { /* no-op */ }
    }

    private fun openStore() {
        val pkg = BuildConfig.PLAY_STORE_PACKAGE
        try {
            startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("market://details?id=$pkg")))
        } catch (e: ActivityNotFoundException) {
            startActivity(Intent(
                Intent.ACTION_VIEW,
                Uri.parse("https://play.google.com/store/apps/details?id=$pkg")
            ))
        }
    }

    companion object {
        const val EXTRA_MESSAGE = "update_message"
    }
}
```

Layout `activity_update_required.xml` mengikuti tema iOS (dark `#0f172a`,
button accent `#fbbf24`, icon download). Buat sederhana — fokus fungsi.

## C.4. Integrasi di LoginActivity (atau equivalent)

```kotlin
override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    // ... setup UI biasa ...

    lifecycleScope.launch {
        when (val res = apiClient.checkAppVersion()) {
            is VersionCheckResult.Outdated -> {
                if (res.force) {
                    val intent = Intent(this@LoginActivity, UpdateRequiredActivity::class.java)
                        .putExtra(UpdateRequiredActivity.EXTRA_MESSAGE, res.message)
                        .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TASK or Intent.FLAG_ACTIVITY_NEW_TASK)
                    startActivity(intent)
                    finish()
                }
            }
            VersionCheckResult.Ok -> { /* normal flow */ }
        }
    }
}
```

> Cek sekali per launch (di `onCreate` LoginActivity).
> Jangan letakkan di `onResume` agar tidak query berulang.

## C.5. (Opsional, untuk A.6) Kirim Versi pada Request Sensitif

Tambahkan OkHttp interceptor:

```kotlin
val versionInterceptor = Interceptor { chain ->
    val req = chain.request().newBuilder()
        .addHeader("X-App-Version", BuildConfig.VERSION_NAME)
        .addHeader("X-App-Platform", "android")
        .build()
    chain.proceed(req)
}
// Pasang ke OkHttpClient.Builder().addInterceptor(versionInterceptor)
```

**Catatan mode offline (sideload APK):** Play Store URL tidak relevan.
Untuk skenario ini, server bisa expose endpoint `/api/v1/app/latest-apk`
yang return URL APK terbaru. `UpdateRequiredActivity` bisa cek mode
(via config dari QR — `mode: "offline"` vs `"online"`) dan tampilkan
tombol berbeda. Implementasi APK auto-update di Android punya constraint
permission tersendiri (`REQUEST_INSTALL_PACKAGES`) — di luar scope plan ini.

## C.6. Build & Verifikasi

```bash
cd android-client
./gradlew assembleDebug
# atau release jika sudah punya signing config
./gradlew assembleRelease
```

Test integrasi:
1. Pasang APK versi `1.0.0`.
2. Di server: `UPDATE app_config SET value='2.0.0' WHERE key='min_supported_android_version';`
3. Buka app → harus muncul `UpdateRequiredActivity`.
4. Rollback: `UPDATE app_config SET value='1.0.0' WHERE key='min_supported_android_version';`
5. Restart app → kembali normal.

---

## URUTAN PENGERJAAN YANG DISARANKAN

1. **BAGIAN A — Server B** (A.1 migration → A.2 repo → A.3 service → A.4 handler → A.5 wiring → A.7 verifikasi).
2. **BAGIAN B — iOS** (B.0 versi → B.1 → B.2 → B.3 → B.4 → B.6 build).
3. **BAGIAN C — Android** (C.0 versi → C.1 → C.2 → C.3 → C.4 → C.6 build).
4. **Test integrasi end-to-end:**
   - `UPDATE app_config SET value='2.0.0' WHERE key='min_supported_ios_version';`
   - iOS v1.0.0 → harus `UpdateRequiredView`.
   - Android v1.0.0 → masih normal (`min_supported_android_version` belum diubah).
   - Rollback: `UPDATE app_config SET value='1.0.0' WHERE key='min_supported_ios_version';`
   - Tunggu cache TTL (max 60 detik) → semua normal lagi.
5. **Pastikan mekanisme ini masuk di iOS v1.0.0 & Android v1.0.0 SEBELUM rilis pertama.**

---

## CHECKLIST KONSISTENSI ANTAR-HOST

### API
- [ ] Path endpoint sama persis: `/api/v1/app/version-check`
- [ ] Query param: `platform=ios|android`, `version=<x.y.z>`
- [ ] Status usang: HTTP **426**
- [ ] Field JSON: `error`, `min_version`, `force`, `message`
- [ ] Header response: `Cache-Control: public, max-age=60`
- [ ] Platform tidak dikenal → HTTP 200 (fail-open)

### Server (BAGIAN A)
- [ ] Migration 005 dijalankan, tabel `app_config` ada
- [ ] Seed 4 baris (`min_supported_ios_version`, `force_update_ios`,
      `min_supported_android_version`, `force_update_android`)
- [ ] Cache TTL 60 detik di `AppConfigRepo`
- [ ] Endpoint terdaftar di route `/api/v1`
- [ ] `curl` test untuk versi usang & terbaru kedua platform

### iOS (BAGIAN B)
- [ ] `MARKETING_VERSION = "1.0.0"` (3 segmen)
- [ ] `APP_STORE_ID` di-set di `project.yml` & `Info.plist`
- [ ] `versionCheckDone` flag mencegah re-run `.task`
- [ ] `UpdateRequiredView` baca `AppStoreID` dari `Info.plist`, bukan hard-code
- [ ] Tombol "Perbarui" disabled jika ID belum di-set
- [ ] Membaca `min_version` (snake_case) → `minVersion` (CodingKey)

### Android (BAGIAN C)
- [ ] `versionName = "1.0.0"` (3 segmen, samakan iOS)
- [ ] `BuildConfig.PLAY_STORE_PACKAGE` di-set di `build.gradle`
- [ ] `UpdateRequiredActivity` block tombol back
- [ ] Fallback Play Store URL kalau market:// tidak tersedia
- [ ] Cek di `onCreate` LoginActivity (sekali per launch)

### Format Versi
- [ ] `x.y.z` (3 segmen) konsisten di Server, iOS, Android
- [ ] Tidak ada `"1.0"` (2 segmen) — semua wajib `"1.0.0"`
- [ ] `compareVersion` tahan terhadap segmen hilang (treat as 0)

---

## RINGKASAN PERUBAHAN DARI VERSI SEBELUMNYA

| # | Topik | Perubahan |
|---|---|---|
| 1 | Format versi | `"1.0"` → `"1.0.0"` (3 segmen) eksplisit |
| 2 | Konfigurasi | Konstanta hard-code → tabel DB `app_config` |
| 3 | App Store ID | Hard-code di view → `Info.plist` / `BuildConfig` |
| 4 | `.task` SwiftUI | Tambah flag `versionCheckDone` cegah re-run |
| 5 | Cache HTTP | Header `Cache-Control: public, max-age=60` |
| 6 | Versioning policy | Tambah aturan grace period 48 jam |
| 7 | Logging | `#if DEBUG print` di iOS, `Log.w` di Android — silent failure terdiagnosis |
| 8 | Platform Android | **Bagian C baru** (paralel dengan iOS) |
| 9 | Platform tak dikenal | Eksplisit fail-open (HTTP 200) |
| 10 | Test runtime change | Curl test pasca-UPDATE SQL ditambahkan |
