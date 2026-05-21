import Foundation

final class ConfigManager {
    static let shared = ConfigManager()
    private let defaults = UserDefaults.standard

    private enum Key {
        static let moodleUrl = "moodle_url"
        static let securityApiUrl = "security_api_url"
        static let realtimeApiUrl = "realtime_api_url"
    }

    private init() {}

    var moodleUrl: String { defaults.string(forKey: Key.moodleUrl) ?? "" }
    var securityApiUrl: String { defaults.string(forKey: Key.securityApiUrl) ?? "" }
    var realtimeApiUrl: String { defaults.string(forKey: Key.realtimeApiUrl) ?? "" }

    var isConfigured: Bool {
        !moodleUrl.isEmpty && !securityApiUrl.isEmpty
    }

    /// True jika deployment LAN sekolah (server pakai HTTP) — internet bebas
    /// HARUS dibatasi. Deployment VPS (HTTPS) tidak membatasi internet karena
    /// memang butuh internet untuk dijangkau.
    ///
    /// Heuristik: securityApiUrl `http://`  → LAN/offline (lockdown internet)
    ///            securityApiUrl `https://` → VPS/online  (internet diizinkan)
    ///
    /// Konsisten dengan ATS `NSAllowsLocalNetworking`: HTTP hanya diizinkan ke
    /// alamat private/lokal, jadi config HTTP pasti deployment lokal.
    var requiresInternetLockdown: Bool {
        securityApiUrl.lowercased().hasPrefix("http://")
    }

    func saveConfig(moodleUrl: String, securityApiUrl: String, realtimeApiUrl: String) {
        defaults.set(moodleUrl, forKey: Key.moodleUrl)
        defaults.set(securityApiUrl, forKey: Key.securityApiUrl)
        defaults.set(realtimeApiUrl, forKey: Key.realtimeApiUrl)
    }

    // MARK: — Session persistence (mirrors Android SharedPreferences)
    var activeSessionId: String? {
        get { defaults.string(forKey: "ACTIVE_SESSION_ID") }
        set {
            if let v = newValue { defaults.set(v, forKey: "ACTIVE_SESSION_ID") }
            else { defaults.removeObject(forKey: "ACTIVE_SESSION_ID") }
        }
    }

    var activeExamId: String? {
        get { defaults.string(forKey: "ACTIVE_EXAM_ID") }
        set {
            if let v = newValue { defaults.set(v, forKey: "ACTIVE_EXAM_ID") }
            else { defaults.removeObject(forKey: "ACTIVE_EXAM_ID") }
        }
    }

    func clearSession() {
        defaults.removeObject(forKey: "ACTIVE_SESSION_ID")
        defaults.removeObject(forKey: "ACTIVE_EXAM_ID")
    }
}
