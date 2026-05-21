import SwiftUI

/// Route untuk alur ujian.
enum ExamRoute: Hashable {
    case lockdown(studentId: String)
    case exam(studentId: String)
}

/// Koordinator navigasi global berbasis NavigationPath.
///
/// Tujuan utama: memungkinkan pop-to-root dari screen manapun.
/// Tanpa ini, `dismiss()` hanya mundur 1 level — saat ujian gagal/selesai
/// di ExamView, app akan mendarat di LockdownCheckView, bukan LoginView.
/// Dengan popToRoot(), app selalu kembali ke main screen (LoginView).
@MainActor
final class AppNavigator: ObservableObject {
    static let shared = AppNavigator()
    @Published var path = NavigationPath()

    /// Pesan peringatan yang harus ditampilkan SETELAH pop ke LoginView.
    /// Dipakai agar alert "UJIAN DIHENTIKAN" tidak hilang bersama ExamView
    /// yang di-pop — LoginView yang menampilkannya setelah navigasi selesai.
    @Published var pendingAlert: String?

    private init() {}

    func goToLockdown(studentId: String) {
        path.append(ExamRoute.lockdown(studentId: studentId))
    }

    func goToExam(studentId: String) {
        path.append(ExamRoute.exam(studentId: studentId))
    }

    /// Kembali ke root (LoginView) — buang semua screen di atasnya.
    ///
    /// Jika `message` diberikan, alert ditampilkan SETELAH navigasi selesai.
    /// Penting: alert TIDAK boleh diset sebelum/bersamaan dengan pop —
    /// alert modal akan memblokir transisi navigasi (app tertahan di ExamView).
    func popToRoot(thenAlert message: String? = nil) {
        Task { @MainActor in
            self.path = NavigationPath()
            guard let message = message else { return }
            // Tunggu animasi pop selesai agar LoginView jadi view teratas
            try? await Task.sleep(nanoseconds: 500_000_000)
            self.pendingAlert = message
        }
    }
}
