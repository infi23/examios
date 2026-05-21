import Foundation
import UIKit

/// Background monitoring service (analog SecurityMonitorService Android).
/// Pada iOS tidak ada true background service — monitor berjalan selama app aktif di foreground.
/// Heartbeat dikirim setiap 10 detik. Internet check dengan cooldown 60 detik.
final class SecurityMonitorService {
    static let shared = SecurityMonitorService()

    private var timer: Timer?
    private var sessionId: String = ""
    private var lastInternetReport: Date = .distantPast
    private let internetCooldown: TimeInterval = 60

    private init() {}

    func start(sessionId: String) {
        self.sessionId = sessionId
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard !sessionId.isEmpty else { return }

        Task {
            // 1. Heartbeat
            let uptime = ProcessInfo.processInfo.systemUptime
            let battery = await MainActor.run { UIDevice.current.batteryLevel }
            let batteryPct = battery >= 0 ? Int(battery * 100) : -1
            await report(type: "HEARTBEAT",
                         meta: "{\"status\":\"ok\",\"uptime_ms\":\(Int(uptime * 1000)),\"battery\":\(batteryPct),\"timestamp\":\(Int(Date().timeIntervalSince1970 * 1000))}")

            // 2. Internet detection dengan cooldown 60 detik
            let now = Date()
            if now.timeIntervalSince(lastInternetReport) >= internetCooldown {
                let hasCellular = NetworkMonitor.shared.cellularActive
                let hasPing = await NetworkMonitor.shared.hasPublicInternet()
                if hasCellular || hasPing {
                    let source = hasCellular ? "Mobile Data Aktif" : "WiFi terhubung internet publik (ping 8.8.8.8)"
                    await report(type: "INTERNET_ACCESS", meta: "{\"source\":\"\(source)\"}")
                    lastInternetReport = now
                }
            }
        }
    }

    func reportViolation(type: String, metadata: String) {
        Task { await report(type: type, meta: metadata) }
    }

    private func report(type: String, meta: String) async {
        let req = SubmitEventRequest(sessionId: sessionId, eventType: type, metadata: meta)
        try? await APIClient.shared.submitEvent(req)
    }
}
