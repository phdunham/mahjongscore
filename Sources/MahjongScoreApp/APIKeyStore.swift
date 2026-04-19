import Foundation
import Security

/// Stores the Anthropic API key in the macOS Keychain so the app can be launched
/// from Finder (where shell env vars aren't available) without losing auth state.
///
/// Lookup precedence in the app is:
/// 1. Keychain (this store)
/// 2. `ANTHROPIC_API_KEY` environment variable (for `swift run` dev workflow)
/// 3. Nothing — UI prompts the user to enter one via the Settings sheet
enum APIKeyStore {
    private static let service = "com.mahjongscore.anthropic"
    private static let account = "default"

    enum StoreError: Error {
        case encodingFailed
        case keychainFailed(OSStatus)
    }

    /// Save (or replace) the API key in the Keychain.
    static func save(_ key: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8) else {
            throw StoreError.encodingFailed
        }

        // Idempotent: delete any existing entry before inserting.
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(baseQuery as CFDictionary)

        var addQuery = baseQuery
        addQuery[kSecValueData as String] = data
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw StoreError.keychainFailed(status)
        }
    }

    /// Load the stored key, or `nil` if no entry exists.
    static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8)
        else { return nil }
        return key
    }

    /// Remove any stored key.
    static func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// Load from Keychain first, then fall back to the env var.
    static func resolveAPIKey() -> String? {
        if let key = load(), !key.isEmpty { return key }
        if let envKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"],
           !envKey.isEmpty { return envKey }
        return nil
    }
}
