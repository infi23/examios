import Foundation

enum APIError: Error, LocalizedError {
    case invalidURL
    case noData
    case serverError(Int, String)
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "URL tidak valid"
        case .noData: return "Tidak ada data dari server"
        case .serverError(let code, let msg): return "Server error \(code): \(msg)"
        case .decodingError(let e): return "Gagal decode response: \(e)"
        }
    }
}

final class APIClient {
    static let shared = APIClient()
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        session = URLSession(configuration: config)
    }

    private var baseURL: String {
        let url = ConfigManager.shared.securityApiUrl
        return url.hasSuffix("/") ? String(url.dropLast()) : url
    }

    // MARK: — Generic request helpers

    private func request(method: String, path: String, body: Data? = nil) async throws -> (Data, HTTPURLResponse) {
        guard let url = URL(string: "\(baseURL)/\(path)") else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw APIError.noData }
        return (data, http)
    }

    private func post<Req: Encodable, Res: Decodable>(_ path: String, body: Req) async throws -> Res {
        let data = try encoder.encode(body)
        let (respData, http) = try await request(method: "POST", path: path, body: data)
        guard (200...299).contains(http.statusCode) else {
            let msg = String(data: respData, encoding: .utf8) ?? ""
            throw APIError.serverError(http.statusCode, msg)
        }
        do { return try decoder.decode(Res.self, from: respData) }
        catch { throw APIError.decodingError(error) }
    }

    private func patch(_ path: String, body: Data) async throws {
        let (respData, http) = try await request(method: "PATCH", path: path, body: body)
        guard (200...299).contains(http.statusCode) else {
            let msg = String(data: respData, encoding: .utf8) ?? ""
            throw APIError.serverError(http.statusCode, msg)
        }
    }

    private func postVoid(_ path: String, body: Data) async throws {
        let (respData, http) = try await request(method: "POST", path: path, body: body)
        guard (200...299).contains(http.statusCode) else {
            let msg = String(data: respData, encoding: .utf8) ?? ""
            throw APIError.serverError(http.statusCode, msg)
        }
    }

    // MARK: — API Methods

    func checkHealth() async throws {
        let (_, http) = try await request(method: "GET", path: "health")
        guard (200...299).contains(http.statusCode) else { throw APIError.serverError(http.statusCode, "") }
    }

    // MARK: — Force Update Check

    enum VersionCheckResult {
        case ok
        case outdated(message: String, force: Bool)
    }

    /// Cek apakah versi app sekarang masih didukung server.
    /// **Fail-open**: jika server tidak terjangkau, error decode, atau URL tidak valid,
    /// kembalikan `.ok` agar app tidak mati saat server down.
    func checkAppVersion() async -> VersionCheckResult {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let base = baseURL
        guard !base.isEmpty,
              var comps = URLComponents(string: "\(base)/api/v1/app/version-check") else {
            return .ok
        }
        comps.queryItems = [
            URLQueryItem(name: "platform", value: "ios"),
            URLQueryItem(name: "version", value: version)
        ]
        guard let url = comps.url else { return .ok }

        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse else { return .ok }
            if http.statusCode == 426 {
                let body = try? decoder.decode(VersionCheckResponse.self, from: data)
                return .outdated(
                    message: body?.message ?? "Versi aplikasi terlalu lama. Perbarui untuk melanjutkan.",
                    force: body?.force ?? true
                )
            }
            return .ok
        } catch {
            #if DEBUG
            print("⚠ checkAppVersion gagal: \(error.localizedDescription)")
            #endif
            return .ok
        }
    }

    func registerDevice(_ req: RegisterDeviceRequest) async throws -> RegisterDeviceResponse {
        try await post("api/v1/devices/register", body: req)
    }

    func startSession(_ req: StartSessionRequest) async throws -> StartSessionResponse {
        try await post("api/v1/sessions/start", body: req)
    }

    func endSession(sessionId: String) async throws {
        struct EndReq: Encodable { let session_id: String }
        let data = try encoder.encode(EndReq(session_id: sessionId))
        try await postVoid("api/v1/sessions/end", body: data)
    }

    func submitEvent(_ req: SubmitEventRequest) async throws {
        let data = try encoder.encode(req)
        try await postVoid("api/v1/events", body: data)
    }

    func batchSubmitEvents(_ req: BatchSubmitRequest) async throws {
        let data = try encoder.encode(req)
        try await postVoid("api/v1/events/batch", body: data)
    }

    func updateSubject(sessionId: String, subjectName: String) async throws {
        let req = UpdateSubjectRequest(subjectName: subjectName)
        let data = try encoder.encode(req)
        try await patch("api/v1/sessions/\(sessionId)/subject", body: data)
    }

    func verifyExitOTP(sessionId: String, otp: String) async throws {
        let req = VerifyOTPRequest(otp: otp)
        let data = try encoder.encode(req)
        try await postVoid("api/v1/sessions/\(sessionId)/verify-exit-otp", body: data)
    }

    // MARK: — Screenshot upload (multipart)
    func uploadScreenshot(imageData: Data, examId: String, studentId: String, eventType: String) async throws {
        guard let url = URL(string: "\(baseURL)/api/v1/screenshots/upload") else { throw APIError.invalidURL }
        let boundary = UUID().uuidString
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        func append(_ string: String) { if let d = string.data(using: .utf8) { body.append(d) } }

        let fields: [(String, String)] = [("exam_id", examId), ("student_id", studentId), ("event_type", eventType)]
        for (name, value) in fields {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            append("\(value)\r\n")
        }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"screenshot\"; filename=\"screenshot.jpg\"\r\n")
        append("Content-Type: image/jpeg\r\n\r\n")
        body.append(imageData)
        append("\r\n--\(boundary)--\r\n")

        req.httpBody = body
        let (respData, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let msg = String(data: respData, encoding: .utf8) ?? ""
            throw APIError.serverError(code, msg)
        }
    }
}
