import Foundation
import Security

/// Keeps items in the keychain access group the app shares with its Share Extension, so the
/// extension can read the session and client certificates. Releases up to 1.1.2 wrote the app's
/// own group: an item still there moves across the first time it is read, the same way
/// `MacKeychainStore` moves legacy items. A build without the sharing entitlement (unsigned
/// local, CI and test builds) keeps using the app's own group.
struct SharedGroupKeychainStore: KeychainStore {
    /// The shared access group.
    let shared: any KeychainStore
    /// No access group: reads find an item in any group the process can reach, and a delete
    /// removes every copy.
    let anyGroup: any KeychainStore
    /// The app's own group exactly, so a moved item's old copy can go without touching the new
    /// one. `nil` when the group is unknown (the old copy then goes on the next sign out).
    let previousGroup: (any KeychainStore)?

    func save(key: String, data: Data) throws {
        do {
            try shared.save(key: key, data: data)
        } catch let error where MacKeychainStore.isMissingEntitlement(error) {
            try anyGroup.save(key: key, data: data)
            return
        }
        try? previousGroup?.delete(key: key)
    }

    func load(key: String) throws -> Data? {
        do {
            if let data = try shared.load(key: key) {
                return data
            }
        } catch let error where MacKeychainStore.isMissingEntitlement(error) {
            return try anyGroup.load(key: key)
        }
        // Not in the shared group, so whatever this finds is the old copy.
        guard let data = try anyGroup.load(key: key) else { return nil }
        if (try? shared.save(key: key, data: data)) != nil {
            try? previousGroup?.delete(key: key)
        }
        return data
    }

    func delete(key: String) throws {
        try anyGroup.delete(key: key)
    }
}

/// The keychain access group the app and its Share Extension share. Read from the
/// `AppIdentifierPrefix` key both Info.plists carry (`$(AppIdentifierPrefix)`); without it (a
/// test host, a package test) there is no shared group and items stay where they always were.
public enum KeychainSharing {
    static let sharedGroupSuffix = "com.phillipmaizza.nextexplorer.shared"
    static let appGroupSuffix = "com.phillipmaizza.nextexplorer"

    static var appIdentifierPrefix: String? {
        guard
            let prefix = Bundle.main.object(forInfoDictionaryKey: "AppIdentifierPrefix") as? String,
            !prefix.isEmpty, !prefix.hasPrefix("$(")
        else { return nil }
        return prefix
    }

    public static var sharedAccessGroup: String? {
        appIdentifierPrefix.map { $0 + sharedGroupSuffix }
    }

    static var previousAccessGroup: String? {
        appIdentifierPrefix.map { $0 + appGroupSuffix }
    }
}
