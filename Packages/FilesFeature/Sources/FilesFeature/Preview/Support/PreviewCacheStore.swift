import ComposableArchitecture
import FilesClient
import Foundation

/// Reports on and clears `Library/Caches/PreviewCache`: the internal, dedup'd cache
/// `FilesClient`'s `previewFile`/`downloadRawFile` already write into (see
/// `FilesService.previewCacheDirectory`). That path convention is duplicated here rather than
/// exposed from `FilesClient`, which is exclusively the server communication layer: this is a
/// local filesystem only concern, same reasoning as `LegacyDownloadStore`.
public struct PreviewCacheStore: Sendable {
    public var size: @Sendable (_ scope: String) -> Int64
    public var clear: @Sendable () throws -> Void
    /// Removes only one account's downloaded preview and raw bytes, for removing an account while
    /// others stay signed in.
    public var clearAccount: @Sendable (_ scope: String) -> Void

    public init(
        size: @escaping @Sendable (String) -> Int64,
        clear: @escaping @Sendable () throws -> Void,
        clearAccount: @escaping @Sendable (String) -> Void = { _ in }
    ) {
        self.size = size
        self.clear = clear
        self.clearAccount = clearAccount
    }
}

extension PreviewCacheStore: DependencyKey {
    private static var cacheDirectory: URL? {
        guard let cachesDirectory = try? FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) else {
            return nil
        }
        return cachesDirectory.appendingPathComponent("PreviewCache", isDirectory: true)
    }

    public static let liveValue = PreviewCacheStore(
        size: { CacheAccountScope.previewCacheSizeBytes(scope: $0) },
        clear: {
            guard let cacheDirectory, FileManager.default.fileExists(atPath: cacheDirectory.path) else { return }
            try FileManager.default.removeItem(at: cacheDirectory)
        },
        clearAccount: { CacheAccountScope.clearPreviewCache(scope: $0) }
    )

    public static let testValue = PreviewCacheStore(
        size: { _ in 0 },
        clear: { throw Unimplemented() }
    )

    private struct Unimplemented: Error {}
}

public extension DependencyValues {
    var previewCacheStore: PreviewCacheStore {
        get { self[PreviewCacheStore.self] }
        set { self[PreviewCacheStore.self] = newValue }
    }
}
