import Foundation
import Security

/// The Mac keeps items in the data protection keychain, as iOS does, so `ThisDeviceOnly`
/// holds and nothing ever asks for keychain access. Releases up to 1.1.0 wrote the legacy file
/// keychain: an item still there moves across the first time it is read, and every save or
/// delete also clears the legacy copy, so signing out leaves nothing behind in either. A build
/// without the keychain entitlement (unsigned local and CI builds) can't reach the data
/// protection keychain and keeps using the legacy one.
struct MacKeychainStore: KeychainStore {
    let modern: any KeychainStore
    let legacy: any KeychainStore

    init(modern: any KeychainStore, legacy: any KeychainStore) {
        self.modern = modern
        self.legacy = legacy
    }

    init(configuration: KeychainConfiguration) {
        self.init(
            modern: SecurityKeychainStore(configuration: configuration, usesDataProtectionKeychain: true),
            legacy: SecurityKeychainStore(configuration: configuration)
        )
    }

    func save(key: String, data: Data) throws {
        do {
            try modern.save(key: key, data: data)
        } catch let error where Self.isMissingEntitlement(error) {
            try legacy.save(key: key, data: data)
            return
        }
        try? legacy.delete(key: key)
    }

    func load(key: String) throws -> Data? {
        do {
            if let data = try modern.load(key: key) {
                return data
            }
        } catch let error where Self.isMissingEntitlement(error) {
            return try legacy.load(key: key)
        }
        guard let data = try legacy.load(key: key) else { return nil }
        // The legacy copy only goes once the new one is safely written; a failed move keeps the
        // session readable and tries again on the next read.
        if (try? modern.save(key: key, data: data)) != nil {
            try? legacy.delete(key: key)
        }
        return data
    }

    func delete(key: String) throws {
        var modernError: (any Error)?
        do {
            try modern.delete(key: key)
        } catch {
            if !Self.isMissingEntitlement(error) {
                modernError = error
            }
        }
        try legacy.delete(key: key)
        if let modernError {
            throw modernError
        }
    }

    static func isMissingEntitlement(_ error: any Error) -> Bool {
        (error as? KeychainError) == .unexpectedStatus(errSecMissingEntitlement)
    }
}
