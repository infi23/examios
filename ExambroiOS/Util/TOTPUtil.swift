import Foundation
import CryptoKit

/// Algoritma TOTP identik dengan Server B Go:
/// Secret = SHA256(studentId + ":" + examId + ":" + yyyy-MM-dd)
/// TimeStep = unix / 60
/// OTP = HMAC-SHA256(secret, timeStep) → truncate 6 digit
enum TOTPUtil {
    static func verify(otp: String, studentId: String, examId: String) -> Bool {
        let secret = generateSecret(studentId: studentId, examId: examId)
        let now = Int64(Date().timeIntervalSince1970)
        // Toleransi ±1 interval (±60 detik)
        for offset: Int64 in [0, -60, 60] {
            let timeStep = (now + offset) / 60
            if generateCode(secret: secret, timeStep: timeStep) == otp {
                return true
            }
        }
        return false
    }

    private static func generateSecret(studentId: String, examId: String) -> Data {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let today = formatter.string(from: Date())
        let raw = "\(studentId):\(examId):\(today)"
        let digest = SHA256.hash(data: Data(raw.utf8))
        return Data(digest)
    }

    private static func generateCode(secret: Data, timeStep: Int64) -> String {
        var step = timeStep.bigEndian
        let stepData = Data(bytes: &step, count: 8)
        let key = SymmetricKey(data: secret)
        let mac = HMAC<SHA256>.authenticationCode(for: stepData, using: key)
        let hash = Array(mac)
        let offset = Int(hash[hash.count - 1] & 0x0F)
        let code = (
            (Int(hash[offset] & 0x7F) << 24) |
            (Int(hash[offset + 1] & 0xFF) << 16) |
            (Int(hash[offset + 2] & 0xFF) << 8) |
            Int(hash[offset + 3] & 0xFF)
        ) % 1_000_000
        return String(format: "%06d", code)
    }
}
