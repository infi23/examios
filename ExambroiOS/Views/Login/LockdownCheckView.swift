import SwiftUI
import UIKit

/// Pre-exam lockdown checker — wajib semua hijau sebelum bisa mulai ujian.
/// Memastikan device siap & siswa berkomitmen sebelum sesi dimulai.
struct LockdownCheckView: View {
    let studentId: String
    let targetUrl: String?
    @StateObject private var vm = LockdownCheckViewModel()

    var body: some View {
        ZStack {
            Color(hex: "#0f172a").ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    header

                    if vm.isDemoAccount {
                        demoNotice
                            .padding(.horizontal, 20)
                    }

                    VStack(spacing: 12) {
                        checkRow(item: vm.cellularCheck)
                        checkRow(item: vm.batteryCheck)
                        checkRow(item: vm.storageCheck)
                        checkRow(item: vm.guidedAccessCheck)
                    }
                    .padding(.horizontal, 20)

                    declarationBox
                        .padding(.horizontal, 20)

                    actionButtons
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                }
                .padding(.vertical, 24)
            }
        }
        .navigationBarBackButtonHidden(true)
        .onAppear { vm.start(studentId: studentId) }
        .onDisappear { vm.stop() }
    }

    // MARK: — Notice akun demo
    private var demoNotice: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundColor(Color(hex: "#38bdf8"))
            VStack(alignment: .leading, spacing: 3) {
                Text("Akun Demo Terdeteksi")
                    .font(.caption).fontWeight(.bold)
                    .foregroundColor(.white)
                Text("Untuk akun ini, Guided Access TIDAK wajib. Akun siswa reguler tetap WAJIB mengaktifkan Guided Access sebelum ujian.")
                    .font(.caption2)
                    .foregroundColor(Color(hex: "#94a3b8"))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(12)
        .background(Color(hex: "#0c4a6e").opacity(0.4))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: "#38bdf8"), lineWidth: 1))
        .cornerRadius(10)
    }

    // MARK: — Header
    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "shield.lefthalf.filled.badge.checkmark")
                .font(.system(size: 50))
                .foregroundColor(Color(hex: "#fbbf24"))
            Text("Persiapan Ujian")
                .font(.title2).fontWeight(.bold)
                .foregroundColor(.white)
            Text("Pastikan SEMUA poin di bawah HIJAU sebelum mulai")
                .font(.caption)
                .foregroundColor(Color(hex: "#94a3b8"))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
    }

    // MARK: — Check row
    @ViewBuilder
    private func checkRow(item: CheckItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.passed ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 24))
                .foregroundColor(item.passed ? Color(hex: "#22c55e") : Color(hex: "#ef4444"))

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundColor(.white)
                Text(item.detail)
                    .font(.caption)
                    .foregroundColor(item.passed ? Color(hex: "#86efac") : Color(hex: "#fca5a5"))
                    .fixedSize(horizontal: false, vertical: true)

                if !item.passed, let hint = item.hint {
                    Text("💡 \(hint)")
                        .font(.caption2)
                        .foregroundColor(Color(hex: "#fde68a"))
                        .padding(.top, 2)
                }
            }
            Spacer()
        }
        .padding(14)
        .background(item.passed ? Color(hex: "#14532d").opacity(0.35) : Color(hex: "#7f1d1d").opacity(0.35))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(item.passed ? Color(hex: "#22c55e") : Color(hex: "#ef4444"), lineWidth: 1)
        )
        .cornerRadius(12)
    }

    // MARK: — Declaration checkbox
    private var declarationBox: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pernyataan Integritas")
                .font(.caption).fontWeight(.bold)
                .foregroundColor(Color(hex: "#94a3b8"))

            Button(action: { vm.declarationAccepted.toggle() }) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: vm.declarationAccepted ? "checkmark.square.fill" : "square")
                        .font(.system(size: 22))
                        .foregroundColor(vm.declarationAccepted ? Color(hex: "#fbbf24") : Color(hex: "#64748b"))

                    Text("Saya bersedia mengikuti ujian secara jujur. Saya memahami bahwa segala bentuk kecurangan akan terdeteksi sistem dan dapat menyebabkan diskualifikasi.")
                        .font(.caption)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(Color(hex: "#1e293b"))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "#334155"), lineWidth: 1))
        .cornerRadius(12)
    }

    // MARK: — Action buttons
    private var actionButtons: some View {
        VStack(spacing: 10) {
            Button(action: {
                if vm.allChecksPass {
                    AppNavigator.shared.goToExam(studentId: studentId, targetUrl: targetUrl)
                }
            }) {
                HStack {
                    Image(systemName: "play.fill")
                    Text("MULAI UJIAN").fontWeight(.bold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(vm.allChecksPass ? Color(hex: "#fbbf24") : Color(hex: "#334155"))
                .foregroundColor(vm.allChecksPass ? .black : Color(hex: "#64748b"))
                .cornerRadius(12)
            }
            .disabled(!vm.allChecksPass)

            Button(action: { AppNavigator.shared.popToRoot() }) {
                Text("Batal & Kembali")
                    .font(.caption)
                    .foregroundColor(Color(hex: "#94a3b8"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
        }
    }
}

// MARK: — Check item model
struct CheckItem {
    let title: String
    let detail: String
    let hint: String?
    let passed: Bool
}

// MARK: — ViewModel
@MainActor
final class LockdownCheckViewModel: ObservableObject {
    @Published var declarationAccepted = false
    @Published private var cellularActive = false
    @Published private var batteryLevel: Float = 0
    @Published private var storageBytes: Int64 = 0
    @Published private var guidedAccessEnabled = false
    @Published private(set) var isDemoAccount = false

    private var timer: Timer?

    func start(studentId: String) {
        UIDevice.current.isBatteryMonitoringEnabled = true
        NetworkMonitor.shared.start()
        isDemoAccount = DemoAccount.isDemo(studentId)
        refresh()

        let nc = NotificationCenter.default
        // 1. Event-driven: status Guided Access berubah
        nc.addObserver(self, selector: #selector(guidedAccessChanged),
                       name: UIAccessibility.guidedAccessStatusDidChangeNotification, object: nil)
        // 2. App kembali aktif (setelah layar setup Guided Access) → re-cek
        nc.addObserver(self, selector: #selector(appBecameActive),
                       name: UIApplication.didBecomeActiveNotification, object: nil)

        // 3. Timer fallback di .common mode → tetap jalan walau user scroll
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func guidedAccessChanged() {
        guidedAccessEnabled = UIAccessibility.isGuidedAccessEnabled
    }

    @objc private func appBecameActive() {
        refresh()
    }

    private func refresh() {
        cellularActive = NetworkMonitor.shared.cellularActive
        batteryLevel = UIDevice.current.batteryLevel
        storageBytes = freeStorageBytes()
        guidedAccessEnabled = UIAccessibility.isGuidedAccessEnabled
    }

    // MARK: — Checks
    var cellularCheck: CheckItem {
        // Bypass jika: akun demo, ATAU deployment VPS (HTTPS — internet diizinkan)
        if isDemoAccount || !ConfigManager.shared.requiresInternetLockdown {
            return CheckItem(
                title: "Data Seluler",
                detail: "ℹ️ Tidak diperiksa",
                hint: nil,
                passed: true
            )
        }
        return CheckItem(
            title: "Data Seluler",
            detail: cellularActive
                ? "❌ Mobile data terdeteksi AKTIF"
                : "✅ Mobile data nonaktif",
            hint: cellularActive ? "Buka Pengaturan → Cellular → matikan Cellular Data" : nil,
            passed: !cellularActive
        )
    }

    var batteryCheck: CheckItem {
        #if targetEnvironment(simulator)
        // Simulator tidak punya baterai fisik → lewati pemeriksaan
        return CheckItem(
            title: "Baterai",
            detail: "ℹ️ Tidak diperiksa (Simulator)",
            hint: nil,
            passed: true
        )
        #else
        // batteryLevel -1 = status belum terbaca (transien saat awal) → jangan blokir,
        // timer 1 detik akan refresh dengan nilai sebenarnya.
        guard batteryLevel >= 0 else {
            return CheckItem(
                title: "Baterai",
                detail: "ℹ️ Membaca status baterai…",
                hint: nil,
                passed: true
            )
        }
        let pct = Int(batteryLevel * 100)
        let ok = pct >= 30
        return CheckItem(
            title: "Baterai",
            detail: ok ? "✅ Baterai \(pct)% (cukup)" : "❌ Baterai \(pct)% (minimal 30%)",
            hint: ok ? nil : "Charge perangkat dulu, atau pinjam charger dari pengawas",
            passed: ok
        )
        #endif
    }

    var storageCheck: CheckItem {
        let mb = storageBytes / 1024 / 1024
        let ok = mb >= 500
        return CheckItem(
            title: "Ruang Penyimpanan",
            detail: ok ? "✅ Tersedia \(mb) MB (cukup)" : "❌ Hanya \(mb) MB (minimal 500 MB)",
            hint: ok ? nil : "Hapus foto/video/app yang tidak perlu",
            passed: ok
        )
    }

    var guidedAccessCheck: CheckItem {
        // Akun demo: bypass — Guided Access tidak wajib
        if isDemoAccount {
            return CheckItem(
                title: "Mode Aman (Guided Access)",
                detail: "ℹ️ Tidak wajib (akun demo)",
                hint: nil,
                passed: true
            )
        }
        return CheckItem(
            title: "Mode Aman (Guided Access)",
            detail: guidedAccessEnabled
                ? "✅ Guided Access AKTIF — siap ujian"
                : "❌ Guided Access BELUM aktif",
            hint: guidedAccessEnabled
                ? nil
                : "Triple-click tombol samping → set passcode + aktifkan Face ID/Touch ID → tap Start",
            passed: guidedAccessEnabled
        )
    }

    var allChecksPass: Bool {
        cellularCheck.passed &&
        batteryCheck.passed &&
        storageCheck.passed &&
        guidedAccessCheck.passed &&
        declarationAccepted
    }

    // MARK: — Helpers
    private func freeStorageBytes() -> Int64 {
        guard let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return 0
        }
        do {
            let values = try url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            return values.volumeAvailableCapacityForImportantUsage ?? 0
        } catch {
            return 0
        }
    }
}
