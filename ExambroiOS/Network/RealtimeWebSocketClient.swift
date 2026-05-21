import Foundation

protocol RealtimeCommandDelegate: AnyObject {
    func onForceLogout(reason: String)
    func onLockDevice(reason: String, playSound: Bool)
    func onUnlockDevice()
    func onStartScreenshot()
    func onSetCaptureStatus(status: String)
}

final class RealtimeWebSocketClient {
    private var webSocketTask: URLSessionWebSocketTask?
    private let urlSession = URLSession(configuration: .default)
    private let sessionId: String
    private let studentId: String
    weak var delegate: RealtimeCommandDelegate?
    private var isConnected = false

    init(sessionId: String, studentId: String) {
        self.sessionId = sessionId
        self.studentId = studentId
    }

    func connect() {
        var baseUrl = ConfigManager.shared.realtimeApiUrl
        guard !baseUrl.isEmpty else { return }
        if baseUrl.hasSuffix("/") { baseUrl = String(baseUrl.dropLast()) }
        let wsUrl = baseUrl
            .replacingOccurrences(of: "http://", with: "ws://")
            .replacingOccurrences(of: "https://", with: "wss://")
        let finalUrl = "\(wsUrl)/ws/client?device_id=\(sessionId)"
        guard let url = URL(string: finalUrl) else { return }

        webSocketTask = urlSession.webSocketTask(with: url)
        webSocketTask?.resume()
        isConnected = true
        receiveMessage()
    }

    func disconnect() {
        isConnected = false
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
    }

    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self, self.isConnected else { return }
            switch result {
            case .success(let message):
                if case .string(let text) = message {
                    self.handleMessage(text)
                }
                self.receiveMessage()
            case .failure:
                // Auto-reconnect after 5s
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                    self?.connect()
                }
            }
        }
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        let action = json["action"] as? String ?? ""
        let reason = json["reason"] as? String ?? "Instruksi Proktor"
        let playSound = json["play_sound"] as? Bool ?? false

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            switch action {
            case "force-logout":
                self.delegate?.onForceLogout(reason: reason)
            case "lock-device":
                self.delegate?.onLockDevice(reason: reason, playSound: playSound)
            case "unlock-device":
                self.delegate?.onUnlockDevice()
            case "start-screenshot":
                self.delegate?.onStartScreenshot()
            case "set-capture-status":
                let ids = json["student_ids"] as? [String] ?? []
                if ids.contains(self.studentId) {
                    let status = json["status"] as? String ?? "inactive"
                    self.delegate?.onSetCaptureStatus(status: status)
                }
            default: break
            }
        }
    }
}
