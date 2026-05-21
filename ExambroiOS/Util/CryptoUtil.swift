import Foundation
import CryptoKit
import CommonCrypto

enum CryptoUtil {
    /// Dekripsi config QR/file. Format: "Base64IV:Base64Ciphertext" — AES-256-CBC
    static func decrypt(_ encryptedText: String, password: String) throws -> String {
        let parts = encryptedText.split(separator: ":").map(String.init)
        guard parts.count == 2,
              let ivData = Data(base64Encoded: parts[0]),
              let cipherData = Data(base64Encoded: parts[1]) else {
            throw CryptoError.invalidFormat
        }

        let keyData = sha256Data(password)

        let bufferSize = cipherData.count + kCCBlockSizeAES128
        var buffer = Data(count: bufferSize)
        var numBytesDecrypted = 0

        let status = buffer.withUnsafeMutableBytes { bufPtr in
            cipherData.withUnsafeBytes { cipherPtr in
                ivData.withUnsafeBytes { ivPtr in
                    keyData.withUnsafeBytes { keyPtr in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyPtr.baseAddress, kCCKeySizeAES256,
                            ivPtr.baseAddress,
                            cipherPtr.baseAddress, cipherData.count,
                            bufPtr.baseAddress, bufferSize,
                            &numBytesDecrypted
                        )
                    }
                }
            }
        }

        guard status == kCCSuccess else { throw CryptoError.decryptionFailed }
        buffer = buffer.prefix(numBytesDecrypted)
        guard let result = String(data: buffer, encoding: .utf8) else { throw CryptoError.decryptionFailed }
        return result
    }

    private static func sha256Data(_ input: String) -> Data {
        let data = Data(input.utf8)
        let digest = SHA256.hash(data: data)
        return Data(digest)
    }

    enum CryptoError: LocalizedError {
        case invalidFormat, decryptionFailed
        var errorDescription: String? {
            switch self {
            case .invalidFormat: return "Format file/QR tidak sesuai standar (membutuhkan format IV:Data)"
            case .decryptionFailed: return "Gagal dekripsi: Password salah atau file rusak."
            }
        }
    }
}
