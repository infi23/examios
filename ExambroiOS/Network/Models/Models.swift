import Foundation

// MARK: — Device Registration
struct RegisterDeviceRequest: Encodable {
    let fingerprintHash: String
    let deviceId: String
    let deviceModel: String
    let manufacturer: String
    let screenResolution: String
    let appSignature: String

    enum CodingKeys: String, CodingKey {
        case fingerprintHash = "fingerprint_hash"
        case deviceId = "android_id"
        case deviceModel = "device_model"
        case manufacturer
        case screenResolution = "screen_resolution"
        case appSignature = "app_signature"
    }
}

struct DeviceDto: Decodable {
    let id: String
}

struct RegisterDeviceResponse: Decodable {
    let device: DeviceDto
}

// MARK: — Session
struct StartSessionRequest: Encodable {
    let deviceId: String
    let studentId: String

    enum CodingKeys: String, CodingKey {
        case deviceId = "device_id"
        case studentId = "student_id"
    }
}

struct SessionDto: Decodable {
    let id: String
    let examId: String

    enum CodingKeys: String, CodingKey {
        case id
        case examId = "exam_id"
    }
}

struct StartSessionResponse: Decodable {
    let session: SessionDto
    let captureStatus: String?

    enum CodingKeys: String, CodingKey {
        case session
        case captureStatus = "capture_status"
    }
}

// MARK: — Events
struct SubmitEventRequest: Encodable {
    let sessionId: String
    let eventType: String
    let metadata: String

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case eventType = "event_type"
        case metadata
    }
}

struct BatchSubmitRequest: Encodable {
    let events: [SubmitEventRequest]
}

// MARK: — Risk Score
struct RiskScoreResponse: Decodable {
    let sessionId: String
    let studentId: String
    let totalScore: Int
    let status: String
    let lastUpdated: String

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case studentId = "student_id"
        case totalScore = "total_score"
        case status
        case lastUpdated = "last_updated"
    }
}

// MARK: — Subject Validation
struct UpdateSubjectRequest: Encodable {
    let subjectName: String

    enum CodingKeys: String, CodingKey {
        case subjectName = "subject_name"
    }
}

// MARK: — OTP
struct VerifyOTPRequest: Encodable {
    let otp: String
}

// MARK: — Realtime Commands
enum RealtimeCommand {
    case forceLogout(reason: String)
    case lockDevice(reason: String, playSound: Bool)
    case unlockDevice
    case startScreenshot
    case setCaptureStatus(status: String)
}

// MARK: — Force Update (Version Check)
// Response dari GET /api/v1/app/version-check.
// HTTP 200 → body { "status": "ok" } (versi masih didukung)
// HTTP 426 → body di bawah (versi usang, wajib update)
struct VersionCheckResponse: Decodable {
    let error: String?
    let minVersion: String?
    let force: Bool?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case error
        case minVersion = "min_version"
        case force, message
    }
}
