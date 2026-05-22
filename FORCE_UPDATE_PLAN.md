# Rencana Implementasi Force-Update (Wajib Versi Terbaru)

> **Dokumen panduan untuk agen AI.**
> Tujuan: mewajibkan aplikasi iOS AgreXambro selalu memakai versi terbaru —
> versi lama otomatis terblokir dan diarahkan untuk update.
>
> Pekerjaan terbagi 2 host terpisah:
> - **BAGIAN A — Server B** (Go/Gin) — ada di host/VPS terpisah.
> - **BAGIAN B — Aplikasi iOS** (Swift) — repo `exambro-ios` di Mac.
>
> Kedua bagian harus konsisten pada kontrak API yang dijelaskan di bawah.

---

## 0. Prinsip & Konteks

1. **Force-update hanya bekerja jika mekanismenya sudah ada di versi yang dipaksa.**
   Maka mekanisme ini WAJIB masuk ke iOS v1.0 SEBELUM submit pertama ke App Store.
2. **Server adalah sumber kebenaran.** Untuk memblokir versi lama cukup mengubah
   nilai `min_supported_ios_version` di server — tanpa update/submit ulang app.
3. **Fail-open:** jika server tidak terjangkau, app TIDAK diblokir (mencegah app
   mati total saat server down). Ini keputusan desain — boleh diubah ke fail-close
   bila diinginkan lebih ketat.
4. App iOS sudah punya `ConfigManager.securityApiUrl` sebagai base URL Server B.

---

## KONTRAK API (acuan kedua bagian)

### Endpoint
```
GET {securityApiUrl}/api/v1/app/version-check?platform=ios&version=<x.y.z>
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

- `force: true`  → hard block (layar wajib update, tidak bisa dilewati)
- `force: false` → soft (boleh lanjut; app cukup menampilkan banner — opsional)

---

# BAGIAN A — SERVER B (Go/Gin) — Host Terpisah

> Dikerjakan oleh agen di host server. Stack: Go + Gin, modul
> `github.com/exambro/server-b-security`. Struktur: `cmd/server/main.go`,
> `internal/handler/`, `internal/service/`.

## A.1. File BARU: `internal/service/version_service.go`

```go
package service

import (
	"strconv"
	"strings"
)

// Versi iOS minimum yang diizinkan. Naikkan untuk memblokir versi lama.
// CATATAN: untuk produksi sebaiknya dipindah ke DB (tabel app_config)
// agar bisa diubah lewat dashboard tanpa redeploy server.
const MinSupportedIOSVersion = "1.0.0"

// true = hard block (wajib update), false = soft (app masih boleh lanjut)
const ForceUpdateIOS = true

// compareVersion: -1 jika a<b, 0 sama, 1 jika a>b. Format "x.y.z".
func compareVersion(a, b string) int {
	pa, pb := strings.Split(a, "."), strings.Split(b, ".")
	for i := 0; i < 3; i++ {
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

// IsIOSVersionOutdated: true jika versi app lebih lama dari minimum.
func IsIOSVersionOutdated(appVersion string) bool {
	if appVersion == "" {
		return false // versi tak terkirim → jangan blokir (fail-open)
	}
	return compareVersion(appVersion, MinSupportedIOSVersion) < 0
}
```

## A.2. Tambahan di `internal/handler/handler.go`

Tambahkan handler baru (pastikan `net/http` dan package `service` sudah di-import):

```go
// VersionCheckHandler — GET /api/v1/app/version-check
type VersionCheckHandler struct{}

func NewVersionCheckHandler() *VersionCheckHandler { return &VersionCheckHandler{} }

func (h *VersionCheckHandler) Check(c *gin.Context) {
	platform := c.Query("platform")
	version := c.Query("version")

	if platform == "ios" && service.IsIOSVersionOutdated(version) {
		c.JSON(http.StatusUpgradeRequired, gin.H{ // HTTP 426
			"error":       "APP_OUTDATED",
			"min_version": service.MinSupportedIOSVersion,
			"force":       service.ForceUpdateIOS,
			"message":     "Versi aplikasi terlalu lama. Wajib perbarui untuk melanjutkan.",
		})
		return
	}
	c.JSON(http.StatusOK, gin.H{"status": "ok"})
}
```

## A.3. Tambahan route di `cmd/server/main.go`

Di dalam grup route `/api/v1` (cari grup yang sudah ada, mis. `api := r.Group("/api/v1")`):

```go
versionHandler := handler.NewVersionCheckHandler()
api.GET("/app/version-check", versionHandler.Check)
```

## A.4. (Opsional) Gate di Start Session

Agar versi usang juga ditolak saat mulai ujian, di handler `Start`
(`SessionHandler`), sebelum memproses sesi, baca header/param versi lalu:

```go
if service.IsIOSVersionOutdated(appVersion) {
    c.JSON(http.StatusUpgradeRequired, gin.H{"error": "APP_OUTDATED", ...})
    return
}
```

Catatan: ini butuh app mengirim versi pada request start session juga
(lihat BAGIAN B.6). Boleh dikerjakan belakangan; endpoint A.2 sudah cukup.

## A.5. Verifikasi Server

```bash
go build ./...
# Jalankan server, lalu test:
curl -i "http://localhost:8081/api/v1/app/version-check?platform=ios&version=0.9.0"
#   → harus HTTP 426 (versi 0.9.0 < 1.0.0)
curl -i "http://localhost:8081/api/v1/app/version-check?platform=ios&version=1.0.0"
#   → harus HTTP 200
```

## A.6. Cara Memakai (Operasional)

Untuk memblokir semua versi lama di masa depan:
1. Ubah konstanta `MinSupportedIOSVersion` (mis. ke `"1.2.0"`).
2. Rebuild & restart Server B.
3. Semua app dengan versi < 1.2.0 langsung terblokir saat launch.

(Jika sudah dipindah ke DB: cukup `UPDATE app_config` tanpa rebuild.)

---

# BAGIAN B — APLIKASI iOS (Swift)

> Repo: `exambro-ios`. Pakai SwiftUI, deployment target iOS 16.0.
> Setelah ubah file, regenerate project: `xcodegen generate` lalu re-set Team
> di Signing & Capabilities. Build cek:
> `xcodebuild -project ExambroiOS.xcodeproj -scheme ExambroiOS -destination 'generic/platform=iOS Simulator,name=iPhone 16' -configuration Debug CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build`

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

Letakkan di dalam `class APIClient` (agar bisa akses `baseURL`, `session`,
`decoder` yang sudah ada sebagai member privat):

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
        return .ok // server tak terjangkau → fail-open, jangan blokir
    }
}
```

## B.3. File BARU: `ExambroiOS/Views/UpdateRequiredView.swift`

```swift
import SwiftUI

struct UpdateRequiredView: View {
    let message: String
    // App ID numerik dari App Store Connect — isi setelah app dibuat di sana.
    private let appStoreID = "0000000000"

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
            }
        }
    }

    private func openAppStore() {
        if let url = URL(string: "itms-apps://apps.apple.com/app/id\(appStoreID)") {
            UIApplication.shared.open(url)
        }
    }
}
```

> CATATAN: `Color(hex:)` sudah didefinisikan di `LoginView.swift` (extension
> Color). Tidak perlu mendefinisikan ulang.

## B.4. Integrasi di `ExambroiOS/Views/Login/LoginView.swift`

Tambahkan dua `@State` di struct `LoginView`:

```swift
@State private var updateRequired = false
@State private var updateMessage = ""
```

Pada `NavigationStack { ... }`, tambahkan modifier (setelah `.onChange`/
`.alert` yang sudah ada):

```swift
.task {
    if case .outdated(let msg, let force) = await APIClient.shared.checkAppVersion(), force {
        updateMessage = msg
        updateRequired = true
    }
}
.fullScreenCover(isPresented: $updateRequired) {
    UpdateRequiredView(message: updateMessage)
}
```

> `.task` jalan sekali saat LoginView muncul. Jika config server belum diisi
> (`securityApiUrl` kosong), `checkAppVersion()` akan gagal → `.ok` → tidak
> memblokir. Itu perilaku yang diinginkan (cek versi baru relevan setelah
> server dikonfigurasi).

## B.5. Regenerate & Build

```bash
cd exambro-ios
xcodegen generate
# Set Team di Xcode → Signing & Capabilities → tab All
xcodebuild -project ExambroiOS.xcodeproj -scheme ExambroiOS \
  -destination 'generic/platform=iOS Simulator,name=iPhone 16' \
  -configuration Debug CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO build
```

## B.6. (Opsional) Kirim Versi saat Start Session

Jika BAGIAN A.4 dikerjakan, app perlu mengirim versi pada request start
session. Tambahkan field di `StartSessionRequest` (Models.swift):

```swift
let appVersion: String   // CodingKey: "app_version"
```

dan isi dari `Bundle.main.infoDictionary?["CFBundleShortVersionString"]`
saat membuat request di `ExamView.initSession()`.

---

## URUTAN PENGERJAAN YANG DISARANKAN

1. **Server B dulu** (BAGIAN A) — deploy endpoint `version-check`.
2. Verifikasi dengan `curl` (A.5).
3. **iOS** (BAGIAN B) — B.1 → B.2 → B.3 → B.4 → B.5.
4. Test integrasi:
   - Set `MinSupportedIOSVersion = "2.0.0"` di server (sementara) → restart.
   - Jalankan app iOS (versi 1.0) → harus muncul `UpdateRequiredView`.
   - Kembalikan `MinSupportedIOSVersion = "1.0.0"` → app jalan normal.
5. Pastikan mekanisme ini masuk build iOS v1.0 SEBELUM submit App Store.

## CHECKLIST KONSISTENSI ANTAR-HOST

- [ ] Path endpoint sama persis: `/api/v1/app/version-check`
- [ ] Query param: `platform=ios`, `version=<x.y.z>`
- [ ] Status usang: HTTP **426**
- [ ] Field JSON: `error`, `min_version`, `force`, `message`
- [ ] iOS membaca `min_version` (snake_case) → `minVersion` (CodingKey)
- [ ] Format versi `x.y.z` (CFBundleShortVersionString) di kedua sisi
