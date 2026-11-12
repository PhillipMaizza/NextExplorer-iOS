import CryptoKit
import Dependencies
import FilesClient
import Foundation
import UniformTypeIdentifiers

/// Thumbnails of files shared into the app, made from the local copy when the upload is staged,
/// so the folder shows the picture at once instead of a placeholder while the server makes its
/// own. Lives in the App Group container because the share extension writes it.
///
/// A seed belongs to the file at its path only while it is plausibly the same file: same byte
/// size, modified no earlier than shortly before the upload started (the server stores a clashing
/// name as "name (1).ext", so an older file already at the path must not get the new picture), and
/// younger than a week. Like the other caches it is account scoped, encrypted at rest, capped,
/// best effort, and cleared at every session boundary.
public struct LocalThumbnailStore: Sendable {
    /// Seeds the thumbnail for a file staged for upload to `path` under the account `scope`.
    public var seed: @Sendable (_ fileURL: URL, _ type: UTType?, _ path: String, _ scope: String, _ startedAt: Date) -> Void
    /// The seeded JPEG for `path` in the current account, if it belongs to a file of `size`
    /// modified at `modified`.
    public var thumbnail: @Sendable (_ path: String, _ size: Int64, _ modified: Date) -> Data?
    /// Drops the seed once the server's own thumbnail is in.
    public var remove: @Sendable (_ path: String) -> Void
    public var clearAll: @Sendable () -> Void
    public var clearScope: @Sendable (_ scope: String) -> Void
    public var totalSizeBytes: @Sendable () -> Int64

    public init(
        seed: @escaping @Sendable (_ fileURL: URL, _ type: UTType?, _ path: String, _ scope: String, _ startedAt: Date) -> Void,
        thumbnail: @escaping @Sendable (_ path: String, _ size: Int64, _ modified: Date) -> Data?,
        remove: @escaping @Sendable (_ path: String) -> Void,
        clearAll: @escaping @Sendable () -> Void,
        clearScope: @escaping @Sendable (_ scope: String) -> Void,
        totalSizeBytes: @escaping @Sendable () -> Int64
    ) {
        self.seed = seed
        self.thumbnail = thumbnail
        self.remove = remove
        self.clearAll = clearAll
        self.clearScope = clearScope
        self.totalSizeBytes = totalSizeBytes
    }
}

extension LocalThumbnailStore {
    enum Constants {
        static let fileExtension = "json"
        /// Longest side, in pixels: the biggest grid cell at about 3x, like the PDF thumbnails.
        static let maxPixel: CGFloat = 320
        static let jpegQuality: CGFloat = 0.8
        static let maxEntries = 500
        static let maxTotalBytes: Int64 = 32 * 1024 * 1024
        static let maxEntryBytes = 512 * 1024
        static let maxAge: TimeInterval = 7 * 24 * 60 * 60
        /// The phone's and the server's clocks can disagree: a file modified up to this long
        /// before the upload started still counts as the uploaded one.
        static let clockTolerance: TimeInterval = 60 * 60
    }

    struct Entry: Codable, Equatable {
        var size: Int64
        var startedAt: Date
        var jpeg: Data

        /// Whether the file at the seed's path, of `size` modified at `modified`, is the one that
        /// was uploaded, and the seed is still fresh at `now`.
        func matches(size: Int64, modified: Date, now: Date) -> Bool {
            self.size == size
                && modified >= startedAt.addingTimeInterval(-Constants.clockTolerance)
                && now.timeIntervalSince(startedAt) < Constants.maxAge
        }
    }

    /// The server path of `fileName` uploaded into `destination` ("" is the root).
    public static func path(of fileName: String, in destination: String) -> String {
        let folder = destination.trimmingCharacters(in: CacheLayout.pathTrimCharacters)
        return folder.isEmpty ? fileName : "\(folder)/\(fileName)"
    }

    /// The JPEG to seed for a local file, or `nil` when it is not an image or PDF (or fails).
    static func jpeg(for fileURL: URL, type: UTType?) -> Data? {
        guard let image = ThumbnailRendering.thumbnail(of: fileURL, type: type, maxPixel: Constants.maxPixel) else { return nil }
        return ThumbnailRendering.jpegData(image, quality: Constants.jpegQuality)
    }

    final class Storage: @unchecked Sendable {
        private let lock = NSLock()
        private let rootOverride: URL?
        private let now: @Sendable () -> Date
        private lazy var cacheDirectory = rootOverride.flatMap {
            ProtectedCacheDirectory(name: CacheLayout.uploadThumbnailsName, base: $0, fileExtension: Constants.fileExtension)
        }

        init(root: URL?, now: @escaping @Sendable () -> Date) {
            rootOverride = root
            self.now = now
        }

        private func fileURL(scope: String, path: String) -> URL? {
            guard let directory = cacheDirectory?.url else { return nil }
            let normalized = path.trimmingCharacters(in: CacheLayout.pathTrimCharacters)
            let digest = SHA256.hash(data: Data("\(scope)\u{0}\(normalized)".utf8)).map { String(format: "%02x", $0) }.joined()
            return directory
                .appendingPathComponent(CacheAccountScope.scopedFileName(digest, scope: scope))
                .appendingPathExtension(Constants.fileExtension)
        }

        func seed(_ entry: Entry, scope: String, path: String) {
            lock.lock()
            defer { lock.unlock() }
            guard let url = fileURL(scope: scope, path: path), let data = try? JSONEncoder().encode(entry),
                  data.count <= Constants.maxEntryBytes else { return }
            try? data.write(to: url, options: .atomic)
            cacheDirectory?.evict(maxEntries: Constants.maxEntries, maxTotalBytes: Constants.maxTotalBytes)
        }

        func thumbnail(scope: String, path: String, size: Int64, modified: Date) -> Data? {
            lock.lock()
            defer { lock.unlock() }
            guard let url = fileURL(scope: scope, path: path), let data = try? Data(contentsOf: url),
                  let entry = try? JSONDecoder().decode(Entry.self, from: data) else { return nil }
            guard entry.matches(size: size, modified: modified, now: now()) else {
                try? FileManager.default.removeItem(at: url)
                return nil
            }
            return entry.jpeg
        }

        func remove(scope: String, path: String) {
            lock.lock()
            defer { lock.unlock() }
            guard let url = fileURL(scope: scope, path: path) else { return }
            try? FileManager.default.removeItem(at: url)
        }

        func clearAll() {
            lock.lock()
            defer { lock.unlock() }
            cacheDirectory?.removeAll()
        }

        func clear(scope: String) {
            lock.lock()
            defer { lock.unlock() }
            cacheDirectory?.removeEntries(withPrefix: CacheAccountScope.namePrefix(for: scope))
        }

        func totalSizeBytes() -> Int64 {
            lock.lock()
            defer { lock.unlock() }
            return cacheDirectory?.totalSizeBytes() ?? 0
        }

        func asStore() -> LocalThumbnailStore {
            LocalThumbnailStore(
                seed: { fileURL, type, path, scope, startedAt in
                    guard let jpeg = LocalThumbnailStore.jpeg(for: fileURL, type: type) else { return }
                    let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { Int64($0) } ?? 0
                    self.seed(Entry(size: size, startedAt: startedAt, jpeg: jpeg), scope: scope, path: path)
                },
                thumbnail: { self.thumbnail(scope: CacheAccountScope.current, path: $0, size: $1, modified: $2) },
                remove: { self.remove(scope: CacheAccountScope.current, path: $0) },
                clearAll: { self.clearAll() },
                clearScope: { self.clear(scope: $0) },
                totalSizeBytes: { self.totalSizeBytes() }
            )
        }
    }

    /// A store rooted at `root` (the App Group container in the app and the extension; a temp
    /// directory in tests). `nil` makes every call a no op.
    public static func onDisk(root: URL?, now: @escaping @Sendable () -> Date) -> LocalThumbnailStore {
        Storage(root: root, now: now).asStore()
    }
}

extension LocalThumbnailStore: DependencyKey {
    public static var liveValue: LocalThumbnailStore {
        onDisk(root: AppGroup.containerURL, now: { Date() })
    }

    public static var testValue: LocalThumbnailStore {
        LocalThumbnailStore(
            seed: { _, _, _, _, _ in }, thumbnail: { _, _, _ in nil }, remove: { _ in },
            clearAll: {}, clearScope: { _ in }, totalSizeBytes: { 0 }
        )
    }

    public static var previewValue: LocalThumbnailStore {
        testValue
    }
}

public extension DependencyValues {
    var localThumbnailStore: LocalThumbnailStore {
        get { self[LocalThumbnailStore.self] }
        set { self[LocalThumbnailStore.self] = newValue }
    }
}
