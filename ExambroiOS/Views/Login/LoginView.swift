import SwiftUI
import UIKit

struct LoginView: View {
    @StateObject private var vm = LoginViewModel()
    @StateObject private var nav = AppNavigator.shared
    @State private var showQRScanner = false
    @State private var showFilePicker = false
    @State private var showPasswordDialog = false
    @State private var showManualCode = false
    @State private var pendingEncrypted = ""
    @State private var adminPassword = ""
    @State private var manualCode = ""
    // Force-update mechanism (server-driven via /api/v1/app/version-check).
    @State private var updateRequired = false
    @State private var updateMessage = ""
    @State private var versionCheckDone = false

    var body: some View {
        NavigationStack(path: $nav.path) {
            ZStack {
                Color(hex: "#0f172a").ignoresSafeArea()

                VStack(spacing: 0) {
                    // Status bar
                    statusBar

                    Spacer()

                    // Logo & title
                    VStack(spacing: 8) {
                        Image("AgreXambroLogo")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 140, height: 140)
                        Text("AgreXambro")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.white)
                        Text("Sistem Ujian Digital")
                            .font(.subheadline)
                            .foregroundColor(Color(hex: "#94a3b8"))
                    }
                    .padding(.bottom, 24)

                    // Internet warning (disembunyikan untuk akun demo)
                    if vm.internetBlocking {
                        internetWarningBanner
                    }

                    // Input fields
                    VStack(spacing: 16) {
                        TextField("", text: $vm.studentId)
                            .placeholder(when: vm.studentId.isEmpty) {
                                Text("Masukkan User ID / NIS")
                                    .foregroundColor(Color(hex: "#475569"))
                            }
                            .foregroundColor(.white)
                            .keyboardType(.asciiCapable)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .padding()
                            .background(Color(hex: "#1e293b"))
                            .cornerRadius(12)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "#334155"), lineWidth: 1))
                            .disabled(vm.internetBlocking)
                            .opacity(vm.internetBlocking ? 0.5 : 1)

                        Button(action: vm.attemptLogin) {
                            HStack {
                                if vm.isLoading {
                                    ProgressView()
                                        .tint(.black)
                                        .scaleEffect(0.9)
                                } else {
                                    Image(systemName: "shield.fill")
                                    Text("Mulai Ujian")
                                        .fontWeight(.semibold)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(vm.canLogin ? Color(hex: "#fbbf24") : Color(hex: "#334155"))
                            .foregroundColor(vm.canLogin ? .black : Color(hex: "#64748b"))
                            .cornerRadius(12)
                        }
                        .disabled(!vm.canLogin || vm.isLoading)
                    }
                    .padding(.horizontal, 24)

                    // Config buttons
                    HStack(spacing: 10) {
                        configButton(icon: "qrcode.viewfinder", label: "Scan QR") {
                            showQRScanner = true
                        }
                        configButton(icon: "doc.badge.arrow.up", label: "Muat File") {
                            showFilePicker = true
                        }
                        configButton(icon: "text.cursor", label: "Kode Manual") {
                            manualCode = ""
                            adminPassword = ""
                            showManualCode = true
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 12)

                    Spacer()
                }
            }
            .onAppear {
                vm.onAppear()
            }
            .alert("Error", isPresented: $vm.showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(vm.errorMessage)
            }
            .alert("Ujian Dihentikan", isPresented: Binding(
                get: { nav.pendingAlert != nil },
                set: { if !$0 { nav.pendingAlert = nil } }
            )) {
                Button("OK", role: .cancel) { nav.pendingAlert = nil }
            } message: {
                Text(nav.pendingAlert ?? "")
            }
            .alert("Masukkan Password Admin", isPresented: $showPasswordDialog) {
                SecureField("Password", text: $adminPassword)
                Button("Buka") {
                    vm.processEncryptedConfig(pendingEncrypted, password: adminPassword)
                    adminPassword = ""
                }
                Button("Batal", role: .cancel) { adminPassword = "" }
            } message: {
                Text("Data konfigurasi ini dilindungi oleh kata sandi.")
            }
            .alert("Masukkan Kode Konfigurasi", isPresented: $showManualCode) {
                TextField("Tempel kode terenkripsi", text: $manualCode)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                SecureField("Password admin", text: $adminPassword)
                Button("Terapkan") {
                    vm.processEncryptedConfig(manualCode.trimmingCharacters(in: .whitespacesAndNewlines),
                                              password: adminPassword)
                    manualCode = ""
                    adminPassword = ""
                }
                Button("Batal", role: .cancel) {
                    manualCode = ""
                    adminPassword = ""
                }
            } message: {
                Text("Tempel kode konfigurasi terenkripsi (format IV:Data) lalu masukkan password admin.")
            }
            .sheet(isPresented: $showQRScanner) {
                QRScanView { scanned in
                    showQRScanner = false
                    pendingEncrypted = scanned
                    showPasswordDialog = true
                }
            }
            .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.text, .data]) { result in
                if let url = try? result.get(), let content = try? String(contentsOf: url) {
                    pendingEncrypted = content
                    showPasswordDialog = true
                }
            }
            .navigationDestination(for: ExamRoute.self) { route in
                switch route {
                case .lockdown(let sid, let target):
                    LockdownCheckView(studentId: sid, targetUrl: target)
                        .navigationBarBackButtonHidden(true)
                case .exam(let sid, let target):
                    ExamView(studentId: sid, targetUrl: target)
                        .navigationBarBackButtonHidden(true)
                }
            }
            // Force-update: cek sekali per session.
            // Hanya berjalan setelah config server terisi (ConfigManager.isReady),
            // karena tanpa baseURL endpoint tidak bisa dipanggil.
            .task {
                guard !versionCheckDone, ConfigManager.shared.isConfigured else { return }
                versionCheckDone = true
                if case .outdated(let msg, let force) = await APIClient.shared.checkAppVersion(), force {
                    updateMessage = msg
                    updateRequired = true
                }
            }
            .fullScreenCover(isPresented: $updateRequired) {
                UpdateRequiredView(message: updateMessage)
            }
        }
        .onChange(of: vm.startExam) { newValue in
            if newValue {
                nav.goToLockdown(studentId: vm.studentId)
                vm.startExam = false // reset trigger
            }
        }
        .onOpenURL { url in
            if url.scheme == "agrexambro" {
                let originalUrl = url.absoluteString
                var targetUrl = originalUrl
                if targetUrl.lowercased().hasPrefix("agrexambro://") {
                    let suffix = targetUrl.dropFirst("agrexambro://".count)
                    targetUrl = "https://\(suffix)"
                }
                
                if ConfigManager.shared.isConfigured {
                    let sid = vm.studentId.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !sid.isEmpty {
                        nav.goToLockdown(studentId: sid, targetUrl: targetUrl)
                    } else {
                        vm.errorMessage = "Masukkan User ID terlebih dahulu sebelum membuka link ujian!"
                        vm.showError = true
                    }
                } else {
                    vm.errorMessage = "Aplikasi belum dikonfigurasi. Silakan scan QR code proktor terlebih dahulu."
                    vm.showError = true
                }
            }
        }
    }

    private var statusBar: some View {
        HStack {
            Circle()
                .fill(vm.serverOnline ? Color(hex: "#4CAF50") : Color(hex: "#F44336"))
                .frame(width: 10, height: 10)
            Text(vm.statusText)
                .font(.caption)
                .foregroundColor(vm.serverOnline ? Color(hex: "#4CAF50") : Color(hex: "#94a3b8"))
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(Color(hex: "#1e293b"))
        .onTapGesture { vm.refreshStatus() }
    }

    private var internetWarningBanner: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "wifi.exclamationmark")
                    .foregroundColor(.red)
                Text("INTERNET TERDETEKSI")
                    .fontWeight(.bold)
                    .foregroundColor(.red)
            }
            Text(vm.internetDetail)
                .font(.caption)
                .foregroundColor(Color(hex: "#fca5a5"))
            Text("Matikan untuk dapat memulai ujian")
                .font(.caption2)
                .foregroundColor(Color(hex: "#fca5a5"))
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.15))
        .overlay(Rectangle().frame(height: 1).foregroundColor(.red), alignment: .top)
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
    }

    private func configButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title2)
                Text(label)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .foregroundColor(Color(hex: "#94a3b8"))
            .background(Color(hex: "#1e293b"))
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: "#334155"), lineWidth: 1))
        }
    }
}

// MARK: — ViewModel
@MainActor
final class LoginViewModel: ObservableObject {
    @Published var studentId = ""
    @Published var isLoading = false
    @Published var serverOnline = false
    @Published var statusText = "Status: Memeriksa server..."
    @Published var internetDetected = false
    @Published var internetDetail = ""
    @Published var showError = false
    @Published var errorMessage = ""
    @Published var startExam = false

    /// Warning internet HANYA muncul jika:
    /// - sudah ada konfigurasi (isConfigured) — kalau kosong, jangan bingungkan user
    /// - deployment LAN/offline (HTTP) — VPS/online tidak butuh blokir internet
    /// - internet terdeteksi
    /// - bukan akun demo (reviewer Apple dilonggarkan)
    var internetBlocking: Bool {
        ConfigManager.shared.isConfigured
            && ConfigManager.shared.requiresInternetLockdown
            && internetDetected
            && !DemoAccount.isDemo(studentId)
    }

    var canLogin: Bool {
        !internetBlocking && !studentId.isEmpty && ConfigManager.shared.isConfigured
    }

    func onAppear() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        NetworkMonitor.shared.start()
        refreshStatus()
        checkInternet()
    }

    func refreshStatus() {
        Task {
            statusText = "Status: Menghubungkan..."
            do {
                try await APIClient.shared.checkHealth()
                serverOnline = true
                statusText = "Status: Online (Siap Ujian)"
            } catch {
                serverOnline = false
                statusText = "Status: Offline (Server tidak terjangkau)"
            }
        }
    }

    func checkInternet() {
        Task {
            let hasCellular = NetworkMonitor.shared.isCellularActive
            let hasPing = await NetworkMonitor.shared.hasPublicInternet()
            internetDetected = hasCellular || hasPing
            if hasCellular {
                internetDetail = "Paket data (Mobile Data) terdeteksi aktif"
            } else if hasPing {
                internetDetail = "Jaringan terhubung ke internet publik"
            }
            // Polling ulang setiap 5 detik
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            checkInternet()
        }
    }

    func processEncryptedConfig(_ encrypted: String, password: String) {
        do {
            let json = try CryptoUtil.decrypt(encrypted, password: password)
            guard let data = json.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let moodleUrl = obj["moodle_url"] as? String, !moodleUrl.isEmpty,
                  let securityUrl = obj["security_api_url"] as? String, !securityUrl.isEmpty else {
                showError(msg: "JSON tidak memiliki field moodle_url atau security_api_url")
                return
            }

            let moodleSecret = obj["moodle_secret"] as? String ?? ""

            // Field `mode` & `expires_at` di QR (jika ada) diabaikan —
            // pelonggaran lockdown kini ditentukan oleh akun demo, bukan mode config.
            ConfigManager.shared.saveConfig(
                moodleUrl: moodleUrl,
                securityApiUrl: securityUrl,
                realtimeApiUrl: obj["realtime_api_url"] as? String ?? "",
                moodleSecret: moodleSecret
            )
            refreshStatus()
        } catch {
            showError(msg: "Akses Ditolak: \(error.localizedDescription)")
        }
    }

    func attemptLogin() {
        guard canLogin else { return }
        // Pakai internetBlocking (bukan internetDetected) — di deployment VPS /
        // akun demo, internet diizinkan jadi tidak boleh diblokir.
        if internetBlocking {
            showError(msg: "Matikan koneksi internet terlebih dahulu!")
            return
        }
        startExam = true
    }

    private func showError(msg: String) {
        errorMessage = msg
        showError = true
    }
}

// MARK: — Helpers
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

extension View {
    func placeholder<Content: View>(when shouldShow: Bool, @ViewBuilder placeholder: () -> Content) -> some View {
        ZStack(alignment: .leading) {
            if shouldShow { placeholder() }
            self
        }
    }
}
