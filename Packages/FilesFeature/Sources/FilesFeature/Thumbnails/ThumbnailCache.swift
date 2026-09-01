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
    /// Resolves and remembers a file's thumbnail URL, so re-opening a folder doesn't re-hit
    /// `GET /api/thumbnails/*` once per file. The server bakes the file's content hash into
    /// the URL it returns, so a remembered mapping is valid only while the file is unchanged:
    /// `signature` (`FileItem.cacheSignature`) keys that. `resolve` runs only on a cache miss
    /// or a changed signature; a `nil` result is remembered too, so an un-thumbnailable file
    /// isn't asked about again on every scroll.
    public var resolvedURL: @Sendable (
        _ path: String, _ signature: String, _ resolve: @Sendable () async -> URL?
    ) async -> URL?

    public init(
        data: @escaping @Sendable (_ url: URL) async throws -> Data,
        resolvedURL: @escaping @Sendable (
            _ path: String, _ signature: String, _ resolve: @Sendable () async -> URL?
        ) async -> URL?
    ) {
        self.data = data
        self.resolvedURL = resolvedURL
    }
}

extension ThumbnailCache: DependencyKey {
    /// Hard ceiling on a single thumbnail response. `thumbnailURL` can fall back to
    /// `GET /api/preview?path=...`, i.e. a full size original, and a hostile or misconfigured
    /// server can point it anywhere, so an uncapped buffer here is an OOM vector per grid cell.
    /// Matches NetworkClient's own in memory response cap.
    private static let maxResponseBytes = 32 * 1024 * 1024

    private static func hexDigest(of string: String) -> String {
        SHA256.hash(data: Data(string.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func previewCacheSubdirectory(_ name: String) throws -> URL {
        let cachesDirectory = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return cachesDirectory.appendingPathComponent("PreviewCache", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
    }

    private static func cacheFileURL(for url: URL) throws -> URL {
        try previewCacheSubdirectory("thumbnails").appendingPathComponent(hexDigest(of: url.absoluteString))
    }

    private static func resolutionRecordURL(for path: String) throws -> URL {
        try previewCacheSubdirectory("thumbnail-urls").appendingPathComponent(hexDigest(of: path))
    }

    private static let resolutionRecordSeparator = "\u{0}"

    public static let liveValue = ThumbnailCache(
        data: { url in
            let fileURL = try cacheFileURL(for: url)
            if let cached = try? Data(contentsOf: fileURL) {
                return cached
            }
            // Stream to a temp file rather than buffering. `thumbnailURL` can fall back to a
            // full size preview, so accumulating the response in memory (worse, byte by byte)
            // burned seconds of CPU and stalled the UI. `download` streams on URLSession's own
            // threads and cancels cleanly when the owning view's `.task` is torn down.
            let (downloadedURL, response) = try await URLSession.shared.download(from: url)
            defer { try? FileManager.default.removeItem(at: downloadedURL) }
            guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
                throw URLError(.badServerResponse)
            }
            let downloadedSize = (try? downloadedURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            guard downloadedSize <= maxResponseBytes else {
                throw URLError(.dataLengthExceedsMaximum)
            }
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: fileURL)
            try FileManager.default.moveItem(at: downloadedURL, to: fileURL)
            return try Data(contentsOf: fileURL)
        },
        resolvedURL: { path, signature, resolve in
            let recordURL = try? resolutionRecordURL(for: path)
            if let recordURL,
               let record = try? String(contentsOf: recordURL, encoding: .utf8) {
                let parts = record.components(separatedBy: resolutionRecordSeparator)
                if parts.count == 2, parts[0] == signature {
                    return parts[1].isEmpty ? nil : URL(string: parts[1])
                }
            }
            let resolved = await resolve()
            if let recordURL {
                try? FileManager.default.createDirectory(at: recordURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? "\(signature)\(resolutionRecordSeparator)\(resolved?.absoluteString ?? "")"
                    .write(to: recordURL, atomically: true, encoding: .utf8)
            }
            return resolved
        }
    )

    public static let testValue = ThumbnailCache(
        data: { _ in throw Unimplemented() },
        resolvedURL: { _, _, resolve in await resolve() }
    )

    private struct Unimplemented: Error {}
}

public extension DependencyValues {
    var thumbnailCache: ThumbnailCache {
        get { self[ThumbnailCache.self] }
        set { self[ThumbnailCache.self] = newValue }
    }
}
