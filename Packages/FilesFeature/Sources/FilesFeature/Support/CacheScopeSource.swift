import Dependencies
import FilesClient

/// The account scope list and directory caches are read and written under. A feature captures it
/// once when its state is created (the account mount), so a response that arrives after an account
/// switch still lands in the account that asked for it.
public struct CacheScopeSource: Sendable {
    public var current: @Sendable () -> String

    public init(current: @escaping @Sendable () -> String) {
        self.current = current
    }
}

extension CacheScopeSource: DependencyKey {
    public static let liveValue = CacheScopeSource(current: { CacheAccountScope.current })
    public static let testValue = CacheScopeSource(current: { "" })
    public static let previewValue = testValue
}

public extension DependencyValues {
    var cacheScope: CacheScopeSource {
        get { self[CacheScopeSource.self] }
        set { self[CacheScopeSource.self] = newValue }
    }
}
