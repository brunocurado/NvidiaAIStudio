import Foundation
import Security

/// Keychain wrapper for securely storing API keys and credentials.
enum KeychainHelper {
    
    private static let service = "com.zentras.nvidia-ai-studio"
    
    /// Save data to Keychain.
    @discardableResult
    static func save(key: String, data: Data) -> Bool {
        // Delete existing item first
        delete(key: key)
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }
    
    /// Save a string to Keychain.
    @discardableResult
    static func save(key: String, string: String) -> Bool {
        guard let data = string.data(using: .utf8) else { return false }
        return save(key: key, data: data)
    }
    
    /// Load data from Keychain.
    static func load(key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
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
    
    /// Save an API key to Keychain using its UUID as the key.
    static func saveAPIKey(_ apiKey: APIKey) -> Bool {
        save(key: "apikey-\(apiKey.id.uuidString)", string: apiKey.key)
    }
    
    /// Load an API key value from Keychain.
    static func loadAPIKey(id: UUID) -> String? {
        loadString(key: "apikey-\(id.uuidString)")
    }
    
    /// Delete an API key from Keychain.
    static func deleteAPIKey(id: UUID) -> Bool {
        delete(key: "apikey-\(id.uuidString)")
    }
}
