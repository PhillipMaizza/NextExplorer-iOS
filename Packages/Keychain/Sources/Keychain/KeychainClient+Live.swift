import Dependencies

public extension KeychainClient {
    static func live(configuration: KeychainConfiguration = .default) -> KeychainClient {
        let store = makeStore(configuration: configuration)
        return KeychainClient(
            save: { try store.save(key: $0, data: $1) },
            load: { try store.load(key: $0) },
            delete: { try store.delete(key: $0) }
        )
    }
}

/// The shared access group (when this build has one) inside the platform store: on the Mac the
/// data protection keychain, with the legacy file keychain behind it.
private func makeStore(configuration: KeychainConfiguration) -> any KeychainStore {
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
    let modern: any KeychainStore = if configuration.accessGroup == nil, let shared = KeychainSharing.sharedAccessGroup {
        SharedGroupKeychainStore(
            shared: store(group: shared),
            anyGroup: store(group: nil),
            previousGroup: KeychainSharing.previousAccessGroup.map { store(group: $0) }
        )
    } else {
        store(group: configuration.accessGroup)
    }
    #if os(macOS)
        return MacKeychainStore(modern: modern, legacy: SecurityKeychainStore(configuration: configuration))
    #else
        return modern
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
