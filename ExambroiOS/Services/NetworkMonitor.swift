import Foundation
import Network

final class NetworkMonitor: ObservableObject, @unchecked Sendable {
    static let shared = NetworkMonitor()

    @Published private(set) var isWifiConnected: Bool = false
    @Published private(set) var isCellularActive: Bool = false

    private let wifiMonitor = NWPathMonitor(requiredInterfaceType: .wifi)
    private let cellMonitor = NWPathMonitor(requiredInterfaceType: .cellular)
    private let queue = DispatchQueue(label: "NetworkMonitor", qos: .utility)
    private let stateLock = NSLock()
    private var _cellularRaw = false
    private var _wifiRaw = false

    /// Thread-safe read of cellular state (callable from any context)
    var cellularActive: Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        return _cellularRaw
    }

    var wifiConnected: Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        return _wifiRaw
    }

    private init() {
        wifiMonitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            let v = (path.status == .satisfied)
            self.stateLock.lock(); self._wifiRaw = v; self.stateLock.unlock()
            DispatchQueue.main.async { self.isWifiConnected = v }
        }
        cellMonitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            let v = (path.status == .satisfied)
            self.stateLock.lock(); self._cellularRaw = v; self.stateLock.unlock()
            DispatchQueue.main.async { self.isCellularActive = v }
        }
    }

    func start() {
        wifiMonitor.start(queue: queue)
        cellMonitor.start(queue: queue)
    }

    func stop() {
        wifiMonitor.cancel()
        cellMonitor.cancel()
    }

    /// Deteksi akses internet publik (internet bebas, di luar server ujian).
    ///
    /// Pakai endpoint HTTPS connectivity-check Google (`generate_204`) — wajib
    /// HTTPS karena ATS `NSAllowsLocalNetworking` memblokir HTTP ke IP publik.
    /// - Reachable → ada internet bebas → app harus blokir (mode reguler).
    /// - Gagal (firewall sekolah memblokir) → tidak ada internet bebas → aman.
    func hasPublicInternet() async -> Bool {
        guard let url = URL(string: "https://www.google.com/generate_204") else { return false }
        var req = URLRequest(url: url)
        req.timeoutInterval = 3
        req.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            return (response as? HTTPURLResponse) != nil
        } catch {
            return false
        }
    }
}
