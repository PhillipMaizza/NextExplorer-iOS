import Foundation
import Security

/// Keeps items in the keychain access group the app shares with its Share Extension, so the
/// extension can read the session and client certificates. Releases up to 1.1.2 wrote the app's
/// own group: an item still there moves across the first time it is read, the same way
/// `MacKeychainStore` moves legacy items. A build without the sharing entitlement (unsigned
/// local, CI and test builds) keeps using the app's own group.
///
/// Downgrading is a deliberate trade off. Once an item has moved, the app's own group no longer
/// holds it, so reinstalling release 1.1.2 over a newer one finds nothing there and asks for a
/// sign in. Keeping the old copy would leave a second credential copy in the keychain for as long
/// as the app is installed, and signing out of the newer release could not reach it from the
/// extension's group. A forced sign in after a downgrade is accepted over that.
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

    func allKeys() throws -> [String] {
        try shared.allKeys()
    }

    /// Moves everything still in the app's own group across, without waiting for each item to be
    /// read. The extension only sees the shared group, so an item the app has not read since the
    /// update would look like a missing session to it. A copy already in the shared group is
    /// newer, so it is never overwritten. Returns how many items moved.
    @discardableResult
    func migrateAll() -> Int {
        guard let previousGroup, let keys = try? previousGroup.allKeys() else { return 0 }
        var moved = 0
        for key in keys {
            guard let data = try? previousGroup.load(key: key) else { continue }
            do {
                if try shared.load(key: key) == nil {
                    try shared.save(key: key, data: data)
                    moved += 1
                }
            } catch let error where MacKeychainStore.isMissingEntitlement(error) {
                return moved
            } catch {
                continue
            }
            try? previousGroup.delete(key: key)
        }
        return moved
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
