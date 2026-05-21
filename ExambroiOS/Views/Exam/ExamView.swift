import SwiftUI
import UIKit
import AVFoundation
import ReplayKit

struct ExamView: View {
    let studentId: String

    @StateObject private var vm: ExamViewModel

    init(studentId: String) {
        self.studentId = studentId
        _vm = StateObject(wrappedValue: ExamViewModel(studentId: studentId))
    }

    var body: some View {
        ZStack {
            // Main WebView
            if let moodleURL = URL(string: ConfigManager.shared.moodleUrl) {
                ExamWebView(
                    url: moodleURL,
                    isLoading: $vm.isWebLoading,
                    onCourseDetected: { vm.onCourseDetected($0) },
                    onQuizStateDetected: { vm.onQuizStateDetected($0) },
                    onMoodleUserDetected: { vm.onMoodleUserDetected($0) },
                    studentId: studentId
                )
                .ignoresSafeArea()
            }

            // Status bar overlay (top)
            VStack(spacing: 0) {
                statusBar
                Spacer()
                // Bottom action bar
                bottomBar
            }

            // Lock overlay (merah — internet/split/lock perintah guru)
            if vm.isLocked {
                lockOverlay
            }

            // Toast feedback screenshot (auto-hide 2 detik)
            if let toast = vm.screenshotToast {
                VStack {
                    Spacer()
                    Text(toast)
                        .font(.caption).fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Color.black.opacity(0.85))
                        .cornerRadius(8)
                        .padding(.bottom, 100)
                        .transition(.opacity)
                }
                .animation(.easeInOut, value: vm.screenshotToast)
            }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear { vm.onAppear() }
        .onDisappear { vm.onDisappear() }
        .alert("Keluar Ujian?", isPresented: $vm.showFinishConfirm) {
            Button("Ya, Keluar", role: .destructive) { vm.confirmFinish() }
            Button("Batal", role: .cancel) {}
        } message: {
            Text("Anda akan kembali ke layar login. Sesi ujian akan ditutup.")
        }
        .alert("🔑 Password Keluar Ujian", isPresented: $vm.showOTPDialog) {
            TextField("6 digit OTP dari Proktor", text: $vm.otpInput)
                .keyboardType(.numberPad)
            Button("Verifikasi") { vm.verifyOTP() }
            Button("Batal", role: .cancel) { vm.otpInput = "" }
        } message: {
            Text("Hubungi Proktor untuk mendapatkan kode OTP keluar.")
        }
        .alert("Peringatan", isPresented: $vm.showWarningAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(vm.warningMessage)
        }
        .alert("Info", isPresented: $vm.showInfoAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(vm.infoMessage)
        }
    }

    // MARK: — Status bar
    private var statusBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "shield.fill")
                .foregroundColor(Color(hex: "#fbbf24"))
                .font(.system(size: 11))
            Text("ExamBro")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
                .fixedSize()
            Spacer(minLength: 4)
            Text(vm.batteryText)
                .font(.system(size: 11))
                .foregroundColor(Color(hex: "#94a3b8"))
                .lineLimit(1)
                .fixedSize()
            Circle()
                .fill(vm.isServerConnected ? Color(hex: "#4CAF50") : Color(hex: "#F44336"))
                .frame(width: 7, height: 7)
            Text(vm.isServerConnected ? "Online" : "Offline")
                .font(.system(size: 11))
                .foregroundColor(vm.isServerConnected ? Color(hex: "#4CAF50") : Color(hex: "#F44336"))
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.85))
    }

    // MARK: — Bottom bar
    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button(action: { vm.refreshWebView() }) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                    Text("Refresh").font(.caption)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Color(hex: "#1e293b"))
                .foregroundColor(.white)
                .cornerRadius(10)
            }

            Spacer()

            Button(action: { vm.onFinishTapped() }) {
                HStack(spacing: 6) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                    Text("Selesai").fontWeight(.bold)
                }
                .padding(.horizontal, 20).padding(.vertical, 12)
                .background(Color(hex: "#fbbf24"))
                .foregroundColor(.black)
                .cornerRadius(10)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.95))
    }

    // MARK: — Lock overlay
    private var lockOverlay: some View {
        ZStack {
            Color.red.opacity(0.15).ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.red)
                Text("PERANGKAT DIKUNCI")
                    .font(.title2).fontWeight(.bold).foregroundColor(.red)
                Text(vm.lockReason)
                    .multilineTextAlignment(.center)
                    .foregroundColor(Color(hex: "#fca5a5"))
                    .padding(.horizontal, 32)
                if vm.lockReason.contains("internet") || vm.lockReason.contains("Mobile Data") {
                    Text("Matikan koneksi internet, lalu tunggu otomatis terbuka.")
                        .font(.caption)
                        .foregroundColor(Color(hex: "#94a3b8"))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }
        }
    }
}

// MARK: — ExamViewModel
@MainActor
final class ExamViewModel: NSObject, ObservableObject, RealtimeCommandDelegate {
    let studentId: String

    @Published var isWebLoading = true
    @Published var isLocked = false
    @Published var lockReason = ""
    @Published var isServerConnected = false
    @Published var batteryText = "🔋"
    @Published var showOTPDialog = false
    @Published var otpInput = ""
    @Published var showWarningAlert = false
    @Published var warningMessage = ""
    @Published var showInfoAlert = false
    @Published var infoMessage = ""
    @Published var showFinishConfirm = false
    @Published var screenshotToast: String?

    var sessionId = ""
    var examId = ""
    private var examStatus = "active" // active | in_progress | finished
    // Screenshot selalu aktif di iOS — tidak butuh permission MediaProjection
    // seperti Android. Server bisa toggle off via realtime command.
    private var isCaptureEnabled = true
    private var isInternetLocked = false
    private var wsClient: RealtimeWebSocketClient?
    private var pingTimer: Timer?
    private var batteryTimer: Timer?
    private var periodicScreenshotTimer: Timer?
    private var audioPlayer: AVAudioPlayer?
    /// Guard agar onAppear hanya inisialisasi sekali — SwiftUI bisa memicu
    /// onAppear berkali-kali untuk view yang sama (navigation re-render).
    private var sessionInitStarted = false

    init(studentId: String) {
        self.studentId = studentId
        super.init()
    }

    func onAppear() {
        // Idempotency guard — onAppear bisa fire >1x karena SwiftUI navigation.
        // Tanpa guard: 2 initSession() paralel → server B Create() 2x → row duplikat
        // di exam_sessions, salah satunya jadi orphan (iOS lapor event ke ID lain).
        guard !sessionInitStarted else { return }
        sessionInitStarted = true

        UIApplication.shared.isIdleTimerDisabled = true
        UIDevice.current.isBatteryMonitoringEnabled = true

        // Observers
        NotificationCenter.default.addObserver(self, selector: #selector(appWillResignActive),
            name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(screenshotDetected),
            name: UIApplication.userDidTakeScreenshotNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(screenCaptureChanged),
            name: UIScreen.capturedDidChangeNotification, object: nil)
        // Guided Access status change — deteksi siswa keluar GA saat ujian
        NotificationCenter.default.addObserver(self, selector: #selector(guidedAccessStatusChanged),
            name: UIAccessibility.guidedAccessStatusDidChangeNotification, object: nil)

        // Battery polling
        batteryTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.updateBattery() }
        }
        updateBattery()

        // Server ping polling
        pingTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.pingServer() }
        }

        // Start session
        Task { await initSession() }
    }

    func onDisappear() {
        UIApplication.shared.isIdleTimerDisabled = false
        SecurityMonitorService.shared.stop()
        wsClient?.disconnect()
        pingTimer?.invalidate()
        batteryTimer?.invalidate()
        periodicScreenshotTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
        stopAlarm()
    }

    // MARK: — Kiosk mode dihapus
    // BYOD tidak pakai Guided Access. Mode ujian mengandalkan deteksi pelanggaran
    // + pengawasan manual via dashboard (proktor disqualify manual).

    // MARK: — Session Initialization
    private func initSession() async {
        // Cek sesi yang tersimpan (restart recovery) — TAPI validasi dulu ke server.
        // Tanpa validasi: kalau DB di-reset / sesi sudah di-end / orphan dari race condition,
        // app reuse ID basi → semua event reject 404 → "tidak masuk database".
        if let saved = ConfigManager.shared.activeSessionId {
            let validateReq = SubmitEventRequest(
                sessionId: saved,
                eventType: "SESSION_RESUME_REQUEST", // weight=0, dummy probe
                metadata: "{\"source\":\"ios_restart_recovery\"}"
            )
            do {
                try await APIClient.shared.submitEvent(validateReq)
                // Sesi VALID di server → lanjut pakai
                sessionId = saved
                examId = ConfigManager.shared.activeExamId ?? ""
                finishSetup()
                return
            } catch {
                // Sesi tidak ada di server (404/error) → bersihkan & buat baru
                ConfigManager.shared.clearSession()
            }
        }

        do {
            let fingerprint = DeviceFingerprint.generate()
            let regReq = RegisterDeviceRequest(
                fingerprintHash: fingerprint,
                deviceId: DeviceFingerprint.rawId(),
                deviceModel: DeviceFingerprint.model(),
                manufacturer: "Apple",
                screenResolution: DeviceFingerprint.screenResolution(),
                appSignature: "exambro_ios_v1"
            )
            let regRes = try await APIClient.shared.registerDevice(regReq)

            let startReq = StartSessionRequest(deviceId: regRes.device.id, studentId: studentId)
            let startRes = try await APIClient.shared.startSession(startReq)

            sessionId = startRes.session.id
            examId = startRes.session.examId
            isCaptureEnabled = (startRes.captureStatus == "active")

            ConfigManager.shared.activeSessionId = sessionId
            ConfigManager.shared.activeExamId = examId

            finishSetup()
        } catch {
            // Peringatan ditampilkan di LoginView via endExam → AppNavigator.pendingAlert
            await endExam(reason: error.localizedDescription)
        }
    }

    private func finishSetup() {
        SecurityMonitorService.shared.start(sessionId: sessionId)
        let ws = RealtimeWebSocketClient(sessionId: sessionId, studentId: studentId)
        ws.delegate = self
        ws.connect()
        wsClient = ws
        startNetworkCellularMonitor()
        startPeriodicScreenshot()
        pingServer()
    }

    /// Screenshot rutin tiap 60 detik sebagai bukti pengawasan (mirip Android
    /// ScreenCaptureService periodic capture). Hasilnya jadi galeri evidence
    /// di MinIO server B yang bisa direview pengawas pasca-ujian.
    private func startPeriodicScreenshot() {
        periodicScreenshotTimer?.invalidate()
        periodicScreenshotTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.takeScreenshot(reason: "PERIODIC")
            }
        }
    }

    // MARK: — Network / Cellular Lock
    private func startNetworkCellularMonitor() {
        NetworkMonitor.shared.start()

        // SKIP cellular auto-lock jika: akun demo, ATAU deployment VPS (HTTPS).
        // Akun siswa reguler pada deployment LAN tetap dikunci saat mobile data aktif.
        guard DemoAccount.isDemo(studentId) == false,
              ConfigManager.shared.requiresInternetLockdown else {
            print("ℹ️ Cellular monitoring DISABLED (akun demo / deployment VPS)")
            return
        }

        Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            let cellular = NetworkMonitor.shared.cellularActive
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if cellular && !self.isInternetLocked {
                    self.lockForInternet("Paket Data (Mobile Data) terdeteksi aktif!")
                } else if !cellular && self.isInternetLocked {
                    await self.checkAndUnlockInternet()
                }
            }
        }
    }

    private func lockForInternet(_ reason: String) {
        isInternetLocked = true
        lockReason = reason
        isLocked = true
        playAlarm()
    }

    private func checkAndUnlockInternet() async {
        let hasPing = await NetworkMonitor.shared.hasPublicInternet()
        if !hasPing && !NetworkMonitor.shared.isCellularActive {
            isInternetLocked = false
            if !isLocked || lockReason.contains("internet") || lockReason.contains("Mobile") {
                isLocked = false
                stopAlarm()
            }
        }
    }

    // MARK: — Split View Detection (iPad)
    func onSizeChanged(newSize: CGSize, originalHeight: CGFloat) {
        guard originalHeight > 0 else { return }
        let reduction = (originalHeight - newSize.height) / originalHeight
        if reduction > 0.25 {
            handleSplitScreen(source: "screenResize")
        }
    }

    private func handleSplitScreen(source: String) {
        lockReason = "SPLIT-SCREEN / MULTI-WINDOW TERDETEKSI!\nKeluar dari mode split untuk melanjutkan."
        isLocked = true
        playAlarm()
        SecurityMonitorService.shared.reportViolation(
            type: "SPLIT_SCREEN",
            metadata: "{\"source\":\"\(source)\",\"detail\":\"Split-screen terdeteksi\"}"
        )
        takeScreenshot(reason: "SPLIT_SCREEN")
    }

    // MARK: — JS Bridge callbacks
    func onCourseDetected(_ courseName: String) {
        guard !sessionId.isEmpty else { return }
        Task {
            do {
                try await APIClient.shared.updateSubject(sessionId: sessionId, subjectName: courseName)
            } catch APIError.serverError(let code, let msg) where code >= 400 {
                showWarning("Pelanggaran: \(msg)")
                await endExam(reason: "Mata pelajaran tidak sah: \(courseName)")
            } catch {}
        }
    }

    func onQuizStateDetected(_ state: String) {
        switch state {
        case "not_started":
            if examStatus != "active" { examStatus = "active"; reportStatus("active") }
        case "in_progress":
            if examStatus != "in_progress" { examStatus = "in_progress"; reportStatus("in_progress") }
        case "finished":
            if examStatus != "finished" { examStatus = "finished"; reportStatus("finished") }
        default: break
        }
    }

    func onMoodleUserDetected(_ moodleUserId: String) {
        let clean = moodleUserId.trimmingCharacters(in: .whitespaces)
        if clean.caseInsensitiveCompare(studentId) != .orderedSame {
            showWarning("PELANGGARAN: Username Moodle (\(clean)) tidak sesuai dengan ID Ujian (\(studentId))!")
            Task { await endExam(reason: "Akses Ditolak - Indikasi Joki") }
        }
    }

    // MARK: — App lifecycle detection
    @objc private func appWillResignActive() {
        guard !sessionId.isEmpty else { return }
        SecurityMonitorService.shared.reportViolation(
            type: "APP_SWITCH",
            metadata: "{\"detail\":\"ExamBro kehilangan fokus (swipe-up / notification)\"}"
        )
        takeScreenshot(reason: "APP_SWITCH")
    }

    @objc private func screenshotDetected() {
        SecurityMonitorService.shared.reportViolation(
            type: "STUDENT_SCREENSHOT",
            metadata: "{\"detail\":\"Siswa mengambil screenshot\"}"
        )
        takeScreenshot(reason: "STUDENT_SCREENSHOT")
    }

    @objc private func screenCaptureChanged() {
        if UIScreen.main.isCaptured {
            SecurityMonitorService.shared.reportViolation(
                type: "SCREEN_RECORDING",
                metadata: "{\"detail\":\"Screen recording/mirroring terdeteksi\"}"
            )
        }
    }

    /// Dipanggil oleh iOS saat siswa start/end Guided Access session.
    /// Kita hanya peduli transisi OFF saat ujian sedang in_progress —
    /// itu indikasi siswa mencoba keluar mode aman di tengah mengerjakan.
    ///
    /// Akun demo: bypass — Guided Access tidak wajib, tidak ada penalty.
    @objc private func guidedAccessStatusChanged() {
        guard !DemoAccount.isDemo(studentId) else { return }

        let active = UIAccessibility.isGuidedAccessEnabled
        if !active {
            handleGuidedAccessExitViolation()
        } else {
            // GA kembali aktif → auto-unlock overlay (jika dikunci karena GA)
            if isLocked && lockReason.contains("MODE AMAN") {
                isLocked = false
                stopAlarm()
            }
        }
    }

    private func handleGuidedAccessExitViolation() {
        // 1. Lock app dengan overlay merah
        lockReason = "⚠️ MODE AMAN DIMATIKAN!\nAktifkan kembali Guided Access untuk melanjutkan ujian.\n(Triple-click tombol samping → Start)"
        isLocked = true
        playAlarm()

        // 2. Report ke server B (event weight 80 di EventWeights)
        SecurityMonitorService.shared.reportViolation(
            type: "GUIDED_ACCESS_EXITED",
            metadata: "{\"detail\":\"Siswa keluar dari Guided Access saat ujian\",\"exam_status\":\"\(examStatus)\"}"
        )

        // 3. Auto-screenshot bukti
        takeScreenshot(reason: "GUIDED_ACCESS_EXITED")
    }

    // MARK: — OTP / Exit
    func onFinishTapped() {
        if examStatus == "in_progress" {
            // Wajib OTP karena masih mengerjakan
            otpInput = ""
            showOTPDialog = true
        } else {
            // Belum mulai / sudah finished → konfirmasi keluar
            showFinishConfirm = true
        }
    }

    func confirmFinish() {
        Task { await endExam() }
    }

    func verifyOTP() {
        let otp = otpInput.trimmingCharacters(in: .whitespaces)
        guard otp.count == 6 else { showWarning("OTP harus 6 digit"); return }
        otpInput = ""
        Task {
            do {
                try await APIClient.shared.verifyExitOTP(sessionId: sessionId, otp: otp)
                await endExam()
            } catch {
                // Fallback verifikasi TOTP lokal (offline)
                if TOTPUtil.verify(otp: otp, studentId: studentId, examId: examId) {
                    await endExam()
                } else {
                    showWarning("OTP salah atau kedaluwarsa")
                }
            }
        }
    }

    // MARK: — Helpers
    private func reportStatus(_ status: String) {
        Task {
            let req = SubmitEventRequest(sessionId: sessionId, eventType: "STATUS_CHANGE",
                                        metadata: "{\"new_status\":\"\(status)\"}")
            try? await APIClient.shared.submitEvent(req)
        }
    }

    private func pingServer() {
        Task {
            do {
                try await APIClient.shared.checkHealth()
                isServerConnected = true
            } catch {
                isServerConnected = false
            }
        }
    }

    private func updateBattery() {
        let level = UIDevice.current.batteryLevel
        let pct = level >= 0 ? Int(level * 100) : 0
        batteryText = "🔋 \(pct)%"
    }

    /// Reload halaman Moodle saat ini.
    /// Pakai WKWebView reference yang sudah di-share via ScreenshotService
    /// (didaftarkan oleh ExamWebView.makeUIView).
    func refreshWebView() {
        guard let webView = ScreenshotService.shared.webView else {
            screenshotToast = "⚠️ WebView belum siap"
            scheduleToastClear()
            return
        }
        webView.reload()
        screenshotToast = "🔄 Memuat ulang halaman..."
        scheduleToastClear()
    }

    // MARK: — Screenshot capture & upload
    private func takeScreenshot(reason: String) {
        guard isCaptureEnabled else {
            screenshotToast = "ℹ️ Capture dinonaktifkan server"
            scheduleToastClear()
            return
        }
        Task { @MainActor in
            await ScreenshotService.shared.captureAndUpload(
                sessionId: sessionId,
                examId: examId,
                studentId: studentId,
                reason: reason
            )
            screenshotToast = ScreenshotService.shared.lastCaptureStatus
            scheduleToastClear()
        }
    }

    private func scheduleToastClear() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            screenshotToast = nil
        }
    }

    // MARK: — End exam
    func endExam(reason: String? = nil) async {
        SecurityMonitorService.shared.stop()
        wsClient?.disconnect()
        stopAlarm()
        UIApplication.shared.isIdleTimerDisabled = false

        if !sessionId.isEmpty {
            let closeType = reason != nil ? "FORCE_CLOSE" : (examStatus == "finished" ? "NORMALLY_CLOSE" : "FORCE_CLOSE")
            let meta = "{\"exam_status\":\"\(examStatus)\",\"reason\":\"\(reason ?? "user_initiated")\"}"
            try? await APIClient.shared.submitEvent(
                SubmitEventRequest(sessionId: sessionId, eventType: closeType, metadata: meta))
            try? await APIClient.shared.endSession(sessionId: sessionId)
            ConfigManager.shared.clearSession()
        }

        // Pop ke LoginView (root). Alert ditampilkan SETELAH pop selesai
        // agar tidak memblokir transisi navigasi.
        let alertMsg = reason.map { "UJIAN DIHENTIKAN: \($0)" }
        AppNavigator.shared.popToRoot(thenAlert: alertMsg)
    }

    // MARK: — Alarm
    private func playAlarm() {
        guard audioPlayer == nil else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
        if let url = Bundle.main.url(forResource: "alarm", withExtension: "mp3") ??
           URL(string: "/System/Library/Audio/UISounds/alarm.caf") {
            audioPlayer = try? AVAudioPlayer(contentsOf: url)
            audioPlayer?.numberOfLoops = -1
            audioPlayer?.play()
        }
    }

    private func stopAlarm() {
        audioPlayer?.stop()
        audioPlayer = nil
    }

    // MARK: — Alert helpers
    private func showWarning(_ msg: String) {
        warningMessage = msg
        showWarningAlert = true
    }

    private func showInfo(_ msg: String) {
        infoMessage = msg
        showInfoAlert = true
    }

    // MARK: — RealtimeCommandDelegate (nonisolated bridge into @MainActor)
    nonisolated func onForceLogout(reason: String) {
        Task { @MainActor in await endExam(reason: reason) }
    }

    nonisolated func onLockDevice(reason: String, playSound: Bool) {
        Task { @MainActor in
            self.lockReason = "Perangkat dikunci oleh Proktor\n\(reason)"
            self.isLocked = true
            if playSound { self.playAlarm() }
        }
    }

    nonisolated func onUnlockDevice() {
        Task { @MainActor in
            guard !self.isInternetLocked else {
                self.showWarning("Perangkat tidak bisa dibuka: koneksi internet masih aktif!")
                return
            }
            self.isLocked = false
            self.stopAlarm()
        }
    }

    nonisolated func onStartScreenshot() {
        Task { @MainActor in
            if self.isCaptureEnabled { self.takeScreenshot(reason: "MANUAL_TEACHER") }
        }
    }

    nonisolated func onSetCaptureStatus(status: String) {
        Task { @MainActor in self.isCaptureEnabled = (status == "active") }
    }
}

// MARK: — Offline HTML Builder
enum ExamOfflineHTMLBuilder {
    static func build() -> String {
        """
<!DOCTYPE html>
<html lang="id">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
<title>Koneksi Terputus</title>
<style>
  *{box-sizing:border-box;margin:0;padding:0}
  html,body{height:100%;background:#0f172a;color:#e2e8f0;font-family:-apple-system,BlinkMacSystemFont,sans-serif}
  body{display:flex;align-items:center;justify-content:center;padding:24px}
  .card{max-width:480px;width:100%;background:#1e293b;border:1px solid #334155;border-radius:20px;padding:36px 28px;text-align:center;box-shadow:0 20px 60px rgba(0,0,0,.45)}
  .icon{font-size:64px;margin-bottom:8px;animation:pulse 2.4s ease-in-out infinite}
  @keyframes pulse{0%,100%{opacity:1;transform:scale(1)}50%{opacity:.55;transform:scale(.94)}}
  h1{font-size:22px;margin:14px 0 6px;color:#f1f5f9;font-weight:700}
  p{font-size:15px;line-height:1.6;color:#94a3b8;margin:0 0 20px}
  .hint{background:rgba(251,191,36,.08);border-left:3px solid #fbbf24;padding:10px 14px;border-radius:8px;font-size:13px;color:#fde68a;text-align:left;margin:0 0 22px}
  .btn{display:inline-block;background:#fbbf24;color:#1f2937;border:none;border-radius:10px;padding:14px 28px;font-size:15px;font-weight:600;cursor:pointer}
</style>
</head>
<body>
  <div class="card">
    <div class="icon">📡</div>
    <h1>Koneksi Terputus</h1>
    <p>Sambungan ke server ujian tidak tersedia.<br>Sesi ujian Anda <strong>tetap aman</strong> — minta bantuan pengawas.</p>
    <div class="hint">💡 <strong>Tips:</strong> Pastikan WiFi tersambung kembali, lalu tekan tombol di bawah.</div>
    <button class="btn" onclick="if(window.webkit&&window.webkit.messageHandlers&&window.webkit.messageHandlers.ExambroNative)window.webkit.messageHandlers.ExambroNative.postMessage({method:'reconnectMoodle',arg:''})">🔄 Coba Sambung Ulang</button>
  </div>
</body>
</html>
"""
    }
}
