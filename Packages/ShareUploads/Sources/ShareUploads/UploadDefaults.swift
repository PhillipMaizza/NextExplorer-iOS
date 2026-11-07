import Dependencies
import DependenciesMacros
import FilesClient
import Foundation

/// Where files shared to NextExplorer from other apps go, per account: the Share Extension and
/// "Open in NextExplorer" both start in `folderPath`, and with `shouldUploadWithoutAsking` they upload
/// straight there. Uploads started inside the app keep going to the folder on screen.
public struct UploadDefaults: Codable, Equatable, Sendable {
    /// A server path, never the root (the server refuses uploads there). `nil`: ask every time.
    public var folderPath: String?
    public var shouldUploadWithoutAsking: Bool

    public init(folderPath: String? = nil, shouldUploadWithoutAsking: Bool = false) {
        self.folderPath = folderPath
        self.shouldUploadWithoutAsking = shouldUploadWithoutAsking
    }

    /// The folder to upload to without asking, when both are set.
    public var directFolder: String? {
        guard shouldUploadWithoutAsking, let folderPath, !folderPath.isEmpty else { return nil }
        return folderPath
    }
}

@DependencyClient
public struct UploadDefaultsClient: Sendable {
    public var load: @Sendable (_ accountID: String) -> UploadDefaults = { _ in UploadDefaults() }
    /// The signed in account's (`CacheAccountScope`), for "Open in NextExplorer".
    public var loadActive: @Sendable () -> UploadDefaults = { UploadDefaults() }
    public var save: @Sendable (_ accountID: String, _ defaults: UploadDefaults) -> Void
    /// Signing an account out forgets its folder, so the next account never inherits it.
    public var remove: @Sendable (_ accountID: String) -> Void
    /// Forgets every account but `accountIDs` (the ones still signed in).
    public var retain: @Sendable (_ accountIDs: Set<String>) -> Void
}

extension UploadDefaultsClient: DependencyKey {
    static let storageKey = "uploadDefaults"

    public static var liveValue: UploadDefaultsClient {
        live(defaults: AppGroup.defaults)
    }

    static func live(defaults: UserDefaults) -> UploadDefaultsClient {
        let store = LockedDefaults(defaults: defaults)
        return UploadDefaultsClient(
            load: { store.read()[$0] ?? UploadDefaults() },
            loadActive: { store.read()[CacheAccountScope.current] ?? UploadDefaults() },
            save: { accountID, value in store.update { $0[accountID] = value } },
            remove: { accountID in store.update { $0[accountID] = nil } },
            retain: { accountIDs in store.update { $0 = $0.filter { accountIDs.contains($0.key) } } }
        )
    }

    public static var testValue: UploadDefaultsClient {
        inMemory()
    }

    public static func inMemory(
        _ initial: [String: UploadDefaults] = [:],
        activeAccountID: String = ""
    ) -> UploadDefaultsClient {
        let values = LockIsolated(initial)
        return UploadDefaultsClient(
            load: { values.value[$0] ?? UploadDefaults() },
            loadActive: { values.value[activeAccountID] ?? UploadDefaults() },
            save: { accountID, value in values.withValue { $0[accountID] = value } },
            remove: { accountID in values.withValue { $0[accountID] = nil } },
            retain: { accountIDs in values.withValue { $0 = $0.filter { accountIDs.contains($0.key) } } }
        )
    }
}

/// `UserDefaults` is thread safe; the lock makes each read, modify, write of the whole map atomic.
private final class LockedDefaults: @unchecked Sendable {
    private let defaults: UserDefaults
    private let lock = NSLock()

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    func read() -> [String: UploadDefaults] {
        lock.withLock { decode() }
    }

    func update(_ change: (inout [String: UploadDefaults]) -> Void) {
        lock.withLock {
            var values = decode()
            change(&values)
            if let data = try? JSONEncoder().encode(values) {
                defaults.set(data, forKey: UploadDefaultsClient.storageKey)
            }
        }
    }

    private func decode() -> [String: UploadDefaults] {
        guard let data = defaults.data(forKey: UploadDefaultsClient.storageKey) else { return [:] }
        return (try? JSONDecoder().decode([String: UploadDefaults].self, from: data)) ?? [:]
    }
}

public extension DependencyValues {
    var uploadDefaults: UploadDefaultsClient {
        get { self[UploadDefaultsClient.self] }
        set { self[UploadDefaultsClient.self] = newValue }
    }
}
