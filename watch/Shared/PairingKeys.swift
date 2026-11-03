import Foundation
import CryptoKit

// Master key K: 32 bytes in the Keychain, shared with the NSE via the app group
// access group (kSecAttrAccessibleAfterFirstUnlock so the NSE can read it while locked).
final class PairingKeys {
    static let shared = PairingKeys()

    private static let service = "opiconnect"
    private static let account = "master"

    private(set) var masterKey: SymmetricKey

    private init() {
        masterKey = PairingKeys.loadOrCreate()
    }

    static var appGroup: String {
        Bundle.main.object(forInfoDictionaryKey: "OpiAppGroup") as? String ?? ""
    }

    private static var baseQuery: [String: Any] {
        var q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if !appGroup.isEmpty { q[kSecAttrAccessGroup as String] = appGroup }
        return q
    }

    private static func loadOrCreate() -> SymmetricKey {
        var q = baseQuery
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        if SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
           let data = item as? Data, data.count == 32 {
            return SymmetricKey(data: data)
        }
        let data = Data((0..<32).map { _ in UInt8.random(in: .min ... .max) })
        var add = baseQuery
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
        return SymmetricKey(data: data)
    }

    // Drop the stored key and generate a fresh one.
    func reset() {
        SecItemDelete(PairingKeys.baseQuery as CFDictionary)
        masterKey = PairingKeys.loadOrCreate()
    }

    var qrString: String {
        "opi1:" + masterKey.withUnsafeBytes { OpiCrypto.base64url(Data($0)) }
    }

    var pairId: String {
        OpiCrypto.base64url(OpiCrypto.hkdf(key: masterKey, info: "opi/id", count: 16))
    }

    var secret: String {
        OpiCrypto.base64url(OpiCrypto.hkdf(key: masterKey, info: "opi/auth", count: 32))
    }

    var encKey: SymmetricKey {
        SymmetricKey(data: OpiCrypto.hkdf(key: masterKey, info: "opi/enc", count: 32))
    }
}
