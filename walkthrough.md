# Walkthrough: Penyesuaian exambro-ios untuk quizaccess_agrexambro

Sesi ini berhasil menyelesaikan integrasi penuh aplikasi iOS (`exambro-ios`) agar selaras dengan plugin Moodle `quizaccess_agrexambro`. Seluruh fitur keamanan dan lockdown bawaan aplikasi iOS dipertahankan sepenuhnya tanpa ada perubahan atau penghapusan fungsionalitas yang merugikan.

---

## Perubahan yang Dilakukan

### 1. Registrasi URL Scheme
* **Berkas**: [Info.plist](file:///d:/_moodle_plugin/exambro-ios/ExambroiOS/Info.plist)
* **Deskripsi**: Mendaftarkan skema URL `agrexambro` di iOS agar tautan bertipe `agrexambro://` dapat membuka aplikasi AgreXambro secara otomatis dari browser Safari/Chrome.

### 2. Penyimpanan Kunci Rahasia Moodle
* **Berkas**: [ConfigManager.swift](file:///d:/_moodle_plugin/exambro-ios/ExambroiOS/Config/ConfigManager.swift)
* **Deskripsi**: Menambahkan kunci `"moodle_secret"` ke dalam persistent storage (`UserDefaults`). Nilai kunci ini di-decrypt secara aman dari konfigurasi QR Code / manual.

### 3. Deteksi Deep Linking & Validasi User ID
* **Berkas**: [LoginView.swift](file:///d:/_moodle_plugin/exambro-ios/ExambroiOS/Views/Login/LoginView.swift)
* **Deskripsi**:
  * Ditambahkan `.onOpenURL` pada view utama untuk menangkap deep link.
  * Tautan masuk dikonversi dari skema `agrexambro://` ke `https://`.
  * Memvalidasi keberadaan User ID siswa sebelum masuk ke area ujian. Jika kosong, menampilkan pesan peringatan.
  * Ekstraksi field `moodle_secret` dari payload konfigurasi JSON yang terenkripsi.

### 4. Propagasi Target URL
* **Berkas**:
  * [AppNavigator.swift](file:///d:/_moodle_plugin/exambro-ios/ExambroiOS/AppNavigator.swift)
  * [LockdownCheckView.swift](file:///d:/_moodle_plugin/exambro-ios/ExambroiOS/Views/Login/LockdownCheckView.swift)
  * [ExamView.swift](file:///d:/_moodle_plugin/exambro-ios/ExambroiOS/Views/Exam/ExamView.swift)
* **Deskripsi**: Menambahkan parameter opsional `targetUrl` ke router `ExamRoute`. Parameter ini diteruskan dari layar Login, melewati layar Lockdown Check, dan dimuat langsung ke WebView Ujian.

### 5. Injeksi Header Keamanan & Kustomisasi User-Agent
* **Berkas**: [ExamWebView.swift](file:///d:/_moodle_plugin/exambro-ios/ExambroiOS/Views/Exam/ExamWebView.swift)
* **Deskripsi**:
  * Menyetel `customUserAgent` pada `WKWebView` agar berisi `"Agrexambro/1.0.0"`. Hal ini meloloskan pemeriksaan User-Agent di server Moodle.
  * Membuat request web dengan menyisipkan header kustom `X-Agrexambro-Key` bermuatan kunci rahasia Moodle saat memuat halaman pertama kali.
  * Memperbarui callback reconnect offline agar memuat kembali halaman dengan menyertakan header otentikasi.

---

## Rencana Pengujian Mandiri

1. **Uji Konfigurasi & QR Code**: Pindai QR Code proktor untuk memastikan proses dekripsi dan penyimpanan kunci rahasia Moodle berjalan lancar.
2. **Uji Klik Link (Deep Linking)**:
   * Jalankan browser luar (Safari), ketik URL peluncuran: `agrexambro://[domain]/mod/quiz/view.php?id=[cmid]`.
   * Klik tautan tersebut. Aplikasi harus otomatis terbuka, memeriksa validasi User ID, dan mengarahkan siswa ke halaman Lockdown Check dengan benar.
3. **Uji Validasi Kuis Moodle**:
   * Selesaikan pemeriksaan persiapan ujian dan mulai ujian.
   * Pastikan WebView memuat halaman kuis Moodle tanpa diblokir oleh plugin `quizaccess_agrexambro`.
