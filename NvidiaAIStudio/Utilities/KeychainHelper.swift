import Foundation
import Security

/// Keychain wrapper for securely storing API keys and credentials.
enum KeychainHelper {
    
    private static let service = "com.zentras.nvidia-ai-studio"
    private static let migrationKey = "keychain_migrated_v2"

    // MARK: - Migration

    /// Migrate all existing Keychain items to kSecAttrAccessibleAfterFirstUnlock.
    /// This only runs once (tracked via UserDefaults) and eliminates repeated
    /// macOS password prompts on unsigned builds.
    static func migrateIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }

        // Find all items for our service
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUISkip
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecSuccess, let items = result as? [[String: Any]] {
            for item in items {
                guard
                    let account = item[kSecAttrAccount as String] as? String,
                    let data = item[kSecValueData as String] as? Data
                else { continue }

                // Delete old item and rewrite with new accessibility attribute
                let deleteQuery: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: service,
                    kSecAttrAccount as String: account
                ]
                SecItemDelete(deleteQuery as CFDictionary)

                let newItem: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: service,
                    kSecAttrAccount as String: account,
                    kSecValueData as String: data,
                    kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
                ]
                SecItemAdd(newItem as CFDictionary, nil)
            }
        }

        UserDefaults.standard.set(true, forKey: migrationKey)
    }

    // MARK: - Core Operations

    /// Save data to Keychain using update-or-insert to avoid re-creating items
    /// (which would trigger macOS password prompts on unsigned builds).
    @discardableResult
    static func save(key: String, data: Data) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        if status == errSecItemNotFound {
            var newItem = query
            newItem[kSecValueData as String] = data
            newItem[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            return SecItemAdd(newItem as CFDictionary, nil) == errSecSuccess
        }

        return status == errSecSuccess
    }

    /// Save a string to Keychain.
    @discardableResult
    static func save(key: String, string: String) -> Bool {
        guard let data = string.data(using: .utf8) else { return false }
        return save(key: key, data: data)
    }

    /// Load data from Keychain silently (no UI prompts).
    static func load(key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUISkip
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    /// Load a string from Keychain.
    static func loadString(key: String) -> String? {
        guard let data = load(key: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Delete an item from Keychain.
    @discardableResult
    static func delete(key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    // MARK: - API Key Helpers

    @discardableResult
    static func saveAPIKey(_ apiKey: APIKey) -> Bool {
        save(key: "apikey-\(apiKey.id.uuidString)", string: apiKey.key)
    }

    static func loadAPIKey(id: UUID) -> String? {
        loadString(key: "apikey-\(id.uuidString)")
    }

    @discardableResult
    static func deleteAPIKey(id: UUID) -> Bool {
        delete(key: "apikey-\(id.uuidString)")
    }
}
