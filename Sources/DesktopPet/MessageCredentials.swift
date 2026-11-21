import Foundation
import Security

protocol MessageCredentialStorage {
    func read(account: String) throws -> String?
    func write(_ token: String, account: String) throws
    func remove(account: String) throws
}

/// Only opaque account names are saved beside message history. Bearer tokens
/// remain in this Mac's Keychain and never enter URLs, logs, or source files.
final class MessageCredentials: MessageCredentialStorage {
    private let service="com.desktop-pet.watercolor-duck.messages"
    private func query(_ account: String) -> [String: Any] {
        [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:account]
    }
    func read(account: String) throws -> String? {
        var values=query(account)
        values[kSecReturnData as String]=true; values[kSecMatchLimit as String]=kSecMatchLimitOne
        var item: CFTypeRef?
        let status=SecItemCopyMatching(values as CFDictionary,&item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data=item as? Data, let token=String(data:data,encoding:.utf8) else {
            throw MessageServiceError.credentials
        }
        return token
    }
    func write(_ token: String, account: String) throws {
        let bytes=Data(token.utf8)
        let status=SecItemUpdate(query(account) as CFDictionary,[kSecValueData as String:bytes] as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw MessageServiceError.credentials }
        var values=query(account); values[kSecValueData as String]=bytes
        values[kSecAttrAccessible as String]=kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(values as CFDictionary,nil) == errSecSuccess else { throw MessageServiceError.credentials }
    }
    func remove(account: String) throws {
        let result=SecItemDelete(query(account) as CFDictionary)
        guard result == errSecSuccess || result == errSecItemNotFound else { throw MessageServiceError.credentials }
    }
}
