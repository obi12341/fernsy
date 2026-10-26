import Foundation
import Security

/// Codable values as generic passwords in the keychain, one item per account name.
enum Keychain {
    #if DEBUG
    /// Debug builds have their own bundle id; their own service keeps them away from the
    /// installed app's items even where the signature would let them ask for access.
    private static let service = "de.mobilistics.fernsy.dev"
    #else
    private static let service = "de.mobilistics.fernsy"
    #endif

    static func load<T: Decodable>(_ type: T.Type, account: String) -> T? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    static func save<T: Encodable>(_ value: T, account: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        delete(account: account)
        let attrs: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        SecItemAdd(attrs as CFDictionary, nil)
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// The Xtream login.
enum CredentialStore {
    static func load() -> XtreamCredentials? { Keychain.load(XtreamCredentials.self, account: "xtream") }
    static func save(_ credentials: XtreamCredentials) { Keychain.save(credentials, account: "xtream") }
    static func delete() { Keychain.delete(account: "xtream") }
}
