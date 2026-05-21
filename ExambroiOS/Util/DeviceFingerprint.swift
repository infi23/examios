import UIKit
import CryptoKit

enum DeviceFingerprint {
    static func generate() -> String {
        let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        let model = UIDevice.current.model
        let raw = "\(deviceId)-\(model)"
        return sha256(raw)
    }

    static func rawId() -> String {
        UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
    }

    static func model() -> String {
        UIDevice.current.model
    }

    static func screenResolution() -> String {
        let bounds = UIScreen.main.bounds
        let scale = UIScreen.main.scale
        return "\(Int(bounds.width * scale))x\(Int(bounds.height * scale))"
    }

    static func sha256(_ input: String) -> String {
        let data = Data(input.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
