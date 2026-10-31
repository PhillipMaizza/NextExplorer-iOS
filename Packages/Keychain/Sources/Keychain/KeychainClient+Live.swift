import Dependencies

public extension KeychainClient {
    static func live(configuration: KeychainConfiguration = .default) -> KeychainClient {
        #if os(macOS)
            let store = MacKeychainStore(configuration: configuration)
        #else
            let store = SecurityKeychainStore(configuration: configuration)
        #endif
        return KeychainClient(
            save: { try store.save(key: $0, data: $1) },
            load: { try store.load(key: $0) },
            delete: { try store.delete(key: $0) }
        )
    }
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
