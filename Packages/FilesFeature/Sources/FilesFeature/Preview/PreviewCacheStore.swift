import ComposableArchitecture
import Foundation

/// Reports on and clears `Library/Caches/PreviewCache` — the internal, dedup'd cache
/// `FilesClient`'s `previewFile`/`downloadRawFile` already write into (see
/// `FilesService.previewCacheDirectory`). That path convention is duplicated here rather than
/// exposed from `FilesClient`, which is exclusively the server-communication layer — this is a
/// local-filesystem-only concern, same reasoning as `LocalDownloadStore`.
public struct PreviewCacheStore: Sendable {
    public var size: @Sendable () throws -> Int64
    public var clear: @Sendable () throws -> Void

    public init(size: @escaping @Sendable () throws -> Int64, clear: @escaping @Sendable () throws -> Void) {
        self.size = size
        self.clear = clear
    }
}

extension PreviewCacheStore: DependencyKey {
    private static var cacheDirectory: URL? {
        guard let cachesDirectory = try? FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: false) else {
            return nil
        }
        return cachesDirectory.appendingPathComponent("PreviewCache", isDirectory: true)
    }

    public static let liveValue = PreviewCacheStore(
        size: {
            guard let cacheDirectory, FileManager.default.fileExists(atPath: cacheDirectory.path) else { return 0 }
            let fileManager = FileManager.default
            guard let enumerator = fileManager.enumerator(
                at: cacheDirectory,
                includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey]
            ) else { return 0 }
            var total: Int64 = 0
            for entry in enumerator {
                guard let url = entry as? URL else { continue }
                let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
                guard resourceValues?.isDirectory == false else { continue }
                total += Int64(resourceValues?.fileSize ?? 0)
            }
            return total
        },
        clear: {
            guard let cacheDirectory, FileManager.default.fileExists(atPath: cacheDirectory.path) else { return }
            try FileManager.default.removeItem(at: cacheDirectory)
        }
    )

    public static let testValue = PreviewCacheStore(
        size: { throw Unimplemented() },
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
