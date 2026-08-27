import ComposableArchitecture
import CryptoKit
import Foundation

/// Disk-backed cache for thumbnail image bytes, keyed by the thumbnail's own URL. Safe to key
/// on the URL alone (rather than the source file's `dateModified`/`size`, which aren't
/// available here) because the server itself bakes a content hash into that URL — see
/// `FilesService.thumbnailURL`'s doc comment: a changed file gets a *different* URL, so a
/// stale cache entry can't outlive the content it was fetched for. Lives under the same
/// `Library/Caches/PreviewCache` root `PreviewCacheStore` reports on/clears, so "Clear Cache"
/// in Settings covers thumbnails too.
public struct ThumbnailCache: Sendable {
    public var data: @Sendable (_ url: URL) async throws -> Data

    public init(data: @escaping @Sendable (_ url: URL) async throws -> Data) {
        self.data = data
    }
}

extension ThumbnailCache: DependencyKey {
    private static func cacheFileURL(for url: URL) throws -> URL {
        let cachesDirectory = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let directory = cachesDirectory.appendingPathComponent("PreviewCache", isDirectory: true)
            .appendingPathComponent("thumbnails", isDirectory: true)
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        let key = digest.map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(key)
    }

    public static let liveValue = ThumbnailCache(
        data: { url in
            let fileURL = try cacheFileURL(for: url)
            if let cached = try? Data(contentsOf: fileURL) {
                return cached
            }
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
                throw URLError(.badServerResponse)
            }
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
            return data
        }
    )

    public static let testValue = ThumbnailCache(data: { _ in throw Unimplemented() })

    private struct Unimplemented: Error {}
}

public extension DependencyValues {
    var thumbnailCache: ThumbnailCache {
        get { self[ThumbnailCache.self] }
        set { self[ThumbnailCache.self] = newValue }
    }
}
