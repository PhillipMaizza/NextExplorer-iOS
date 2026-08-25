import Foundation
import Security

/// Thin wrapper over `Security`'s generic-password item calls. Not a singleton — callers
/// construct one with an explicit `KeychainConfiguration` and hand it to `KeychainClient`.
struct SecurityKeychainStore: Sendable {
    let configuration: KeychainConfiguration

    func save(key: String, data: Data) throws {
        var query = baseQuery(for: key)

        if SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess {
            let attributesToUpdate: [CFString: Any] = [kSecValueData: data]
            let status = SecItemUpdate(query as CFDictionary, attributesToUpdate as CFDictionary)
            guard status == errSecSuccess else {
                throw KeychainError.unexpectedStatus(status)
            }
            return
        }

        query[kSecValueData] = data
        query[kSecAttrAccessible] = configuration.accessible.cfString
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    func load(key: String) throws -> Data? {
        var query = baseQuery(for: key)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
        guard let data = result as? Data else {
            throw KeychainError.unexpectedItemFormat
        }
        return data
    }

    func delete(key: String) throws {
        let query = baseQuery(for: key)
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    private func baseQuery(for key: String) -> [CFString: Any] {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: configuration.service,
            kSecAttrAccount: key
        ]
        if let accessGroup = configuration.accessGroup {
            query[kSecAttrAccessGroup] = accessGroup
        }
        return query
    }
}
