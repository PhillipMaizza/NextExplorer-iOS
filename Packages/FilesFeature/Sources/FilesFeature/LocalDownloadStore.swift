import ComposableArchitecture
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

    public var id: String { url.path }

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
    public var save: @Sendable (_ sourceURL: URL, _ fileName: String, _ location: DownloadLocation) throws -> URL
    /// Both `Documents/Downloads` and `Caches/Downloads` — the user's "Download Location"
    /// preference can change over time, so past downloads under the other location would
    /// otherwise silently disappear from the Downloads tab.
    public var list: @Sendable () throws -> [LocalDownload]
    public var delete: @Sendable (_ url: URL) throws -> Void

    public init(
        save: @escaping @Sendable (_ sourceURL: URL, _ fileName: String, _ location: DownloadLocation) throws -> URL,
        list: @escaping @Sendable () throws -> [LocalDownload],
        delete: @escaping @Sendable (_ url: URL) throws -> Void
    ) {
        self.save = save
        self.list = list
        self.delete = delete
    }
}

extension LocalDownloadStore: DependencyKey {
    private static func downloadsDirectory(for location: DownloadLocation, create: Bool) throws -> URL {
        let fileManager = FileManager.default
        let searchDirectory: FileManager.SearchPathDirectory = location == .documents ? .documentDirectory : .cachesDirectory
        let base = try fileManager.url(for: searchDirectory, in: .userDomainMask, appropriateFor: nil, create: create)
        return base.appendingPathComponent("Downloads", isDirectory: true)
    }

    public static let liveValue = LocalDownloadStore(
        save: { sourceURL, fileName, location in
            let fileManager = FileManager.default
            let downloadsDirectory = try downloadsDirectory(for: location, create: true)
            try fileManager.createDirectory(at: downloadsDirectory, withIntermediateDirectories: true)
            let destination = downloadsDirectory.appendingPathComponent(fileName)
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: sourceURL, to: destination)
            return destination
        },
        list: {
            let fileManager = FileManager.default
            var downloads: [LocalDownload] = []
            for location in DownloadLocation.allCases {
                let directory = try downloadsDirectory(for: location, create: false)
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
        }
    )

    public static let testValue = LocalDownloadStore(
        save: { _, _, _ in throw Unimplemented() },
        list: { throw Unimplemented() },
        delete: { _ in throw Unimplemented() }
    )

    private struct Unimplemented: Error {}
}

public extension DependencyValues {
    var localDownloadStore: LocalDownloadStore {
        get { self[LocalDownloadStore.self] }
        set { self[LocalDownloadStore.self] = newValue }
    }
}
