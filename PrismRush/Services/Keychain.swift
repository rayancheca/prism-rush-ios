import Foundation
import Security

/// Minimal Keychain wrapper for small private account identifiers (the Apple user id + given name).
/// These belong in the Keychain rather than `UserDefaults` (swift/security guidance): they're
/// private identifiers, and the Keychain persists across reinstall the way Apple intends instead of
/// being wiped with the app sandbox. Items are generic-password, this-device-only, available after
/// first unlock — never synced to iCloud Keychain or other devices.
enum Keychain {
    /// Store (or, with `nil`, delete) a string for `account`. Returns true on success.
    @discardableResult
    static func set(_ value: String?, for account: String) -> Bool {
        guard let value, let data = value.data(using: .utf8) else { return delete(account) }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        if SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess {
            return SecItemUpdate(query as CFDictionary, attributes as CFDictionary) == errSecSuccess
        }
        var add = query
        add.merge(attributes) { _, new in new }
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    /// The string stored for `account`, or nil if absent/unreadable.
    static func get(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else { return nil }
        return string
    }

    /// Remove the item for `account`. Returns true on success or if it was already absent.
    @discardableResult
    static func delete(_ account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
