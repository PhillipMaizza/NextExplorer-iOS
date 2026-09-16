import ComposableArchitecture
import CoreModels
import Foundation

/// One file sitting in the user-visible `Documents/Downloads` or `Caches/Downloads` folder,
/// as surfaced by the Downloads tab. Deleting it here only removes this local copy — it
/// never touches the server, unlike every other delete action in the app.
public struct LocalDownload: Equatable, Identifiable, Sendable {
    public let url: URL
    public let fileName: String
    public let location: DownloadLocation
    public let size: Int64
    public let modifiedDate: Date

    public var id: String {
        url.path
    }

    public init(url: URL, fileName: String, location: DownloadLocation, size: Int64, modifiedDate: Date) {
        self.url = url
        self.fileName = fileName
        self.location = location
        self.size = size
        self.modifiedDate = modifiedDate
    }
}

/// Copies an already-fetched file — wherever `FilesClient.downloadRawFile` left it, inside
/// the app's internal dedup'd preview cache (`Library/Caches/PreviewCache/...`) — into a
/// folder the user can actually find and manage: `Documents/Downloads` or `Caches/Downloads`,
/// per the "Download Location" setting. Deliberately separate from that internal cache
/// directory, which is purely an implementation detail the user has no visibility into.
public struct LocalDownloadStore: Sendable {
    /// `scope` is the current account's `DownloadAccountScope.identifier`, so each account saves
    /// into its own subfolder and can't see another account's files on a shared device. An empty
    /// scope maps to the unscoped legacy folder.
    public var save: @Sendable (_ sourceURL: URL, _ fileName: String, _ location: DownloadLocation, _ scope: String) throws -> URL
    /// Both `Documents/Downloads` and `Caches/Downloads` — the user's "Download Location"
    /// preference can change over time, so past downloads under the other location would
    /// otherwise silently disappear from the Downloads tab. Scoped to one account (see `save`).
    public var list: @Sendable (_ scope: String) throws -> [LocalDownload]
    public var delete: @Sendable (_ url: URL) throws -> Void
    /// Renames the local copy in place (same folder), returning its new URL. Local only, like
    /// `delete` — the server file is never touched.
    public var rename: @Sendable (_ url: URL, _ newName: String) throws -> URL

    public init(
        save: @escaping @Sendable (_ sourceURL: URL, _ fileName: String, _ location: DownloadLocation, _ scope: String) throws -> URL,
        list: @escaping @Sendable (_ scope: String) throws -> [LocalDownload],
        delete: @escaping @Sendable (_ url: URL) throws -> Void,
        rename: @escaping @Sendable (_ url: URL, _ newName: String) throws -> URL
    ) {
        self.save = save
        self.list = list
        self.delete = delete
        self.rename = rename
    }
}

extension LocalDownloadStore: DependencyKey {
    /// The first free URL in `directory` for `fileName`: the name itself if unused, otherwise
    /// the name with a " (1)", " (2)", ... suffix inserted before the extension.
    private static func availableDestination(in directory: URL, fileName: String) -> URL {
        let fileManager = FileManager.default
        let candidate = directory.appendingPathComponent(fileName)
        guard fileManager.fileExists(atPath: candidate.path) else { return candidate }

        let base = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        var index = 1
        while true {
            let suffixed = ext.isEmpty ? "\(base) (\(index))" : "\(base) (\(index)).\(ext)"
            let url = directory.appendingPathComponent(suffixed)
            if !fileManager.fileExists(atPath: url.path) {
                return url
            }
            index += 1
        }
    }

    /// The account-scoped downloads folder. An empty `scope` returns the legacy unscoped folder
    /// (`Downloads/`); a non-empty one nests under it (`Downloads/<scope>/`).
    private static func downloadsDirectory(for location: DownloadLocation, scope: String, create: Bool) throws -> URL {
        let fileManager = FileManager.default
        let searchDirectory: FileManager.SearchPathDirectory = location == .documents ? .documentDirectory : .cachesDirectory
        let base = try fileManager.url(for: searchDirectory, in: .userDomainMask, appropriateFor: nil, create: create)
        let root = base.appendingPathComponent("Downloads", isDirectory: true)
        return scope.isEmpty ? root : root.appendingPathComponent(scope, isDirectory: true)
    }

    /// Moves any files sitting loose in the legacy unscoped `Downloads/` root into the current
    /// account's scoped folder, so downloads saved before per-account scoping stay visible.
    /// Only regular files at the root move; other accounts' scope subfolders are left alone.
    private static func migrateLegacyDownloads(for location: DownloadLocation, scope: String) {
        guard !scope.isEmpty else { return }
        let fileManager = FileManager.default
        guard let legacyRoot = try? downloadsDirectory(for: location, scope: "", create: false),
              fileManager.fileExists(atPath: legacyRoot.path),
              let contents = try? fileManager.contentsOfDirectory(
                  at: legacyRoot,
                  includingPropertiesForKeys: [.isDirectoryKey],
                  options: [.skipsHiddenFiles]
              )
        else { return }
        let looseFiles = contents.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true }
        guard !looseFiles.isEmpty, let scoped = try? downloadsDirectory(for: location, scope: scope, create: true) else { return }
        try? fileManager.createDirectory(at: scoped, withIntermediateDirectories: true)
        for fileURL in looseFiles {
            let destination = availableDestination(in: scoped, fileName: fileURL.lastPathComponent)
            try? fileManager.moveItem(at: fileURL, to: destination)
        }
    }

    public static let liveValue = LocalDownloadStore(
        save: { sourceURL, fileName, location, scope in
            let fileManager = FileManager.default
            let downloadsDirectory = try downloadsDirectory(for: location, scope: scope, create: true)
            try fileManager.createDirectory(at: downloadsDirectory, withIntermediateDirectories: true)
            // `fileName` originates from the server's `FileItem.name` — keep a hostile `../`
            // from landing the copy outside the Downloads folder.
            let safeName = SafeFileName.component(fileName)
            // Two different server files that happen to share a name must not clobber each
            // other locally, so disambiguate with a "(1)", "(2)", ... suffix like Finder does.
            let destination = availableDestination(in: downloadsDirectory, fileName: safeName)
            try fileManager.copyItem(at: sourceURL, to: destination)
            return destination
        },
        list: { scope in
            let fileManager = FileManager.default
            var downloads: [LocalDownload] = []
            for location in DownloadLocation.allCases {
                migrateLegacyDownloads(for: location, scope: scope)
                let directory = try downloadsDirectory(for: location, scope: scope, create: false)
                guard fileManager.fileExists(atPath: directory.path) else { continue }
                let contents = try fileManager.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
                    options: [.skipsHiddenFiles]
                )
                for fileURL in contents {
                    let resourceValues = try fileURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                    downloads.append(
                        LocalDownload(
                            url: fileURL,
                            fileName: fileURL.lastPathComponent,
                            location: location,
                            size: Int64(resourceValues.fileSize ?? 0),
                            modifiedDate: resourceValues.contentModificationDate ?? Date(timeIntervalSince1970: 0)
                        )
                    )
                }
            }
            return downloads
        },
        delete: { url in
            try FileManager.default.removeItem(at: url)
        },
        rename: { url, newName in
            let fileManager = FileManager.default
            // A rename must stay a rename: reject a typed name that carries a path so it can't
            // move the file out of the Downloads folder.
            guard SafeFileName.isSafeComponent(newName) else {
                throw CocoaError(.fileWriteInvalidFileName)
            }
            let destination = url.deletingLastPathComponent().appendingPathComponent(newName)
            guard destination != url else { return url }
            if fileManager.fileExists(atPath: destination.path) {
                throw CocoaError(.fileWriteFileExists)
            }
            try fileManager.moveItem(at: url, to: destination)
            return destination
        }
    )

    public static let testValue = LocalDownloadStore(
        save: { _, _, _, _ in throw Unimplemented() },
        list: { _ in throw Unimplemented() },
        delete: { _ in throw Unimplemented() },
        rename: { _, _ in throw Unimplemented() }
    )

    private struct Unimplemented: Error {}
}

public extension DependencyValues {
    var localDownloadStore: LocalDownloadStore {
        get { self[LocalDownloadStore.self] }
        set { self[LocalDownloadStore.self] = newValue }
    }
}
