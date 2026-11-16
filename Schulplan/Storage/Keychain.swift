import Foundation
import Security

/// Minimaler Keychain-Wrapper. `AfterFirstUnlock`, damit die Hintergrund-Aktualisierung
/// auch bei gesperrtem Gerät an die Zugangsdaten kommt.
enum Keychain {
    private static let service = "de.codeunity.Schulplan"

    static func set(_ data: Data?, for key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
        guard let data else { return }
        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func get(_ key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    static func setCodable<T: Encodable>(_ value: T?, for key: String) {
        set(value.flatMap { try? JSONEncoder().encode($0) }, for: key)
    }

    static func getCodable<T: Decodable>(_ type: T.Type, for key: String) -> T? {
        get(key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }
}
