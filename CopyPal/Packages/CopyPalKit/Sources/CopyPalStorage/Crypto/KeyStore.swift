import Foundation
#if canImport(Security)
import Security
#endif

/// Where the storage key lives.
public protocol KeyStore: Sendable {
    func loadKey() throws -> StorageKey?
    func saveKey(_ key: StorageKey) throws
    func deleteKey() throws
}

/// Tests and the CI self-test: the key lives only as long as the process.
public final class InMemoryKeyStore: KeyStore, @unchecked Sendable {
    private let lock = NSLock()
    private var key: StorageKey?

    public init(key: StorageKey? = nil) {
        self.key = key
    }

    public func loadKey() throws -> StorageKey? {
        lock.withLock { key }
    }

    public func saveKey(_ key: StorageKey) throws {
        lock.withLock { self.key = key }
    }

    public func deleteKey() throws {
        lock.withLock { key = nil }
    }
}

#if canImport(Security) && os(macOS)
/// Generic password in the login Keychain: not synchronized, readable without a
/// prompt by every build signed with the same team and bundle ID.
public struct KeychainKeyStore: KeyStore {
    public let service: String
    public let account: String

    /// `service` is "<bundle-id>.storage" (scripts/reset-dev-state.sh deletes it).
    public init(service: String, account: String = "database-key") {
        self.service = service
        self.account = account
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    public func loadKey() throws -> StorageKey? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { throw StorageError.invalidKey }
            return try StorageKey(data: data)
        case errSecItemNotFound:
            return nil
        default:
            throw StorageError.keychain(status: status)
        }
    }

    public func saveKey(_ key: StorageKey) throws {
        try? deleteKey()
        var attributes = baseQuery
        attributes[kSecValueData as String] = key.data
        attributes[kSecAttrSynchronizable as String] = false
        attributes[kSecAttrLabel as String] = "CopyPal"
        attributes[kSecAttrDescription as String] = "Schlüssel für den verschlüsselten Verlauf"
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw StorageError.keychain(status: status) }
    }

    public func deleteKey() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw StorageError.keychain(status: status)
        }
    }
}
#endif
