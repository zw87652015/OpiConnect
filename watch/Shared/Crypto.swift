import Foundation
import CryptoKit

// Crypto per docs/PROTOCOL.md: base64url without padding, HKDF-SHA256 with a zero-length
// salt, AES-256-GCM sealed as nonce(12) || ciphertext || tag(16) (= SealedBox.combined).
enum OpiCryptoError: Error {
    case sealFailed
}

enum OpiCrypto {
    static func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func base64urlDecode(_ string: String) -> Data? {
        var s = string.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s.append("=") }
        return Data(base64Encoded: s)
    }

    static func hkdf(key: SymmetricKey, info: String, count: Int) -> Data {
        let derived = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: key,
            salt: Data(),
            info: Data(info.utf8),
            outputByteCount: count)
        return derived.withUnsafeBytes { Data($0) }
    }

    static func seal(_ plaintext: Data, using key: SymmetricKey, nonce: AES.GCM.Nonce? = nil) throws -> Data {
        let box = nonce == nil
            ? try AES.GCM.seal(plaintext, using: key)
            : try AES.GCM.seal(plaintext, using: key, nonce: nonce!)
        guard let combined = box.combined else { throw OpiCryptoError.sealFailed }
        return combined
    }

    static func open(_ sealed: Data, using key: SymmetricKey) throws -> Data {
        try AES.GCM.open(AES.GCM.SealedBox(combined: sealed), using: key)
    }

    static func sha256(_ data: Data) -> Data {
        SHA256.hash(data: data).withUnsafeBytes { Data($0) }
    }
}
