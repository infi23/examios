import UIKit
import WebKit

/// Service untuk mengambil screenshot layar ujian + upload ke Server B.
/// Padanan Android: ScreenCaptureService (MediaProjection-based).
///
/// iOS pakai 2 mekanisme:
/// 1. `WKWebView.takeSnapshot()` — capture konten WebView Moodle (lebih reliable
///    karena WebKit OOP rendering tidak ter-capture sempurna oleh drawHierarchy).
/// 2. Fallback `window.drawHierarchy()` — untuk overlay UI di luar WebView
///    (status bar app, tombol Selesai, lock overlay).
@MainActor
final class ScreenshotService {
    static let shared = ScreenshotService()

    /// Reference ke WKWebView aktif. Diset oleh ExamWebView saat makeUIView.
    weak var webView: WKWebView?

    /// Status terakhir capture — observable untuk feedback toast di UI.
    @Published var lastCaptureStatus: String?

    private init() {}

    /// Capture screenshot (composite WebView + overlay UI) → return JPEG data.
    func capture() async -> Data? {
        // Strategi: snapshot whole window. drawHierarchy(afterScreenUpdates: true)
        // pada iOS 13+ menangani WKWebView OOP dengan benar.
        guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene }).first,
              let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first
        else { return nil }

        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        let image = renderer.image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        return image.jpegData(compressionQuality: 0.7)
    }

    /// Convenience: capture + upload ke Server B.
    ///
    /// ⚠️ QUIRK SERVER B: Endpoint /screenshots/upload mengharapkan
    /// **session_id di field form bernama `exam_id`** (legacy naming —
    /// lihat handler.go line 284). Android client juga mengirim sessionId
    /// di parameter `examId`. iOS harus follow konvensi ini.
    func captureAndUpload(sessionId: String, examId: String, studentId: String, reason: String) async {
        guard !sessionId.isEmpty else {
            lastCaptureStatus = "❌ Sesi belum aktif"
            return
        }
        guard let data = await capture() else {
            lastCaptureStatus = "❌ Gagal capture layar"
            return
        }
        do {
            try await APIClient.shared.uploadScreenshot(
                imageData: data,
                examId: sessionId, // ← Server expect sessionID di sini (legacy)
                studentId: studentId,
                eventType: reason
            )
            lastCaptureStatus = "📸 Screenshot terkirim (\(reason))"
        } catch {
            lastCaptureStatus = "❌ Upload gagal: \(error.localizedDescription)"
        }
    }
}
