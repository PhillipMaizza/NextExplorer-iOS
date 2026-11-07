import Dependencies

public extension KeychainClient {
    static func live(
        configuration: KeychainConfiguration = .default,
        gate: KeychainMigrationGate = .shared
    ) -> KeychainClient {
        let store = makeStores(configuration: configuration).store
        return KeychainClient(
            save: { try store.save(key: $0, data: $1) },
            load: { try store.load(key: $0) },
            delete: { try store.delete(key: $0) }
        )
        .waiting(for: gate)
    }

    /// The same client, every call of which first waits for a running launch migration.
    func waiting(for gate: KeychainMigrationGate) -> KeychainClient {
        let inner = self
        return KeychainClient(
            save: { gate.waitUntilFinished(); try inner.save($0, $1) },
            load: { gate.waitUntilFinished(); return try inner.load($0) },
            delete: { gate.waitUntilFinished(); try inner.delete($0) }
        )
    }

    /// Moves items an older release left in the app's own keychain group into the shared group
    /// the Share Extension reads. Call it early at launch: the extension only sees the shared
    /// group, so an item the app has not read since the update would look like a missing session
    /// to it. It does nothing once nothing is left to move, and in a build without the sharing entitlement.
    @discardableResult
    static func migrateToSharedGroupIfNeeded(configuration: KeychainConfiguration = .default) -> Int {
        makeStores(configuration: configuration).shared?.migrateAll() ?? 0
    }

    /// Mac only: moves items the legacy file keychain still holds (releases up to 1.1.0) into the
    /// data protection keychain without waiting for each to be read, so every session key is moved
    /// by launch. Run it after `migrateToSharedGroupIfNeeded`. Safe to repeat, and a failure leaves
    /// the legacy copy in place for the next read to move.
    @discardableResult
    static func migrateLegacyMacItemsIfNeeded(configuration: KeychainConfiguration = .default) -> Int {
        makeStores(configuration: configuration).mac?.migrateAll() ?? 0
    }
}

private struct Stores {
    var store: any KeychainStore
    var shared: SharedGroupKeychainStore?
    var mac: MacKeychainStore?
}

/// The shared access group (when this build has one) inside the platform store: on the Mac the
/// data protection keychain, with the legacy file keychain behind it.
private func makeStores(configuration: KeychainConfiguration) -> Stores {
    #if os(macOS)
        let usesDataProtectionKeychain = true
    #else
        let usesDataProtectionKeychain = false
    #endif
    func store(group: String?) -> SecurityKeychainStore {
        var grouped = configuration
        grouped.accessGroup = group
        return SecurityKeychainStore(configuration: grouped, usesDataProtectionKeychain: usesDataProtectionKeychain)
    }
    var sharedGroupStore: SharedGroupKeychainStore?
    let modern: any KeychainStore
    if configuration.accessGroup == nil, let shared = KeychainSharing.sharedAccessGroup {
        let grouped = SharedGroupKeychainStore(
            shared: store(group: shared),
            anyGroup: store(group: nil),
            previousGroup: KeychainSharing.previousAccessGroup.map { store(group: $0) }
        )
        sharedGroupStore = grouped
        modern = grouped
    } else {
        modern = store(group: configuration.accessGroup)
    }
    #if os(macOS)
        let mac = MacKeychainStore(modern: modern, legacy: SecurityKeychainStore(configuration: configuration))
        return Stores(store: mac, shared: sharedGroupStore, mac: mac)
    #else
        return Stores(store: modern, shared: sharedGroupStore, mac: nil)
    #endif
}

extension KeychainClient: DependencyKey {
    public static let liveValue: KeychainClient = .live()
}

public extension DependencyValues {
    var keychainClient: KeychainClient {
        get { self[KeychainClient.self] }
        set { self[KeychainClient.self] = newValue }
    }
}
