import CoreGraphics
import CoreModels
import Dependencies
import FilesClient
import FolderPickerFeature
import Foundation
import ShareUploads

struct ArchiveThumbnailLoader: Sendable {
    static let maxEntryBytes: Int64 = 20_000_000
    static let maxPixel: CGFloat = 480
    private static let folder = "Thumbnails"

    let archive: FileItem
    let serverURL: URL
    let source: ArchiveBrowserFeature.Source

    @Dependency(\.filesClient) private var filesClient
    @Dependency(\.archiveReader) private var archiveReader

    init?(archive: FileItem, serverURL: URL, source: ArchiveBrowserFeature.Source) {
        guard archive.isZip, source != .unresolved else { return nil }
        self.archive = archive
        self.serverURL = serverURL
        self.source = source
    }

    static func wantsThumbnail(_ entry: ArchiveListingEntry) -> Bool {
        let item = entry.fileItem
        return !entry.isDirectory && !entry.isEncrypted && item.isImage && !item.isSVG
            && (entry.size ?? .max) <= maxEntryBytes
    }

    func image(for entry: ArchiveListingEntry) async -> CGImage? {
        guard Self.wantsThumbnail(entry),
              let destination = SafeDestination.within(
                  ArchiveBrowserFeature.scratchDirectory(for: archive)
                      .appendingPathComponent(Self.folder, isDirectory: true),
                  entry.path
              )
        else { return nil }
        do {
            switch source {
            case .unresolved:
                return nil
            case .server:
                let downloaded = try await filesClient.downloadArchiveEntry(serverURL, archive, entry.path)
                return await Self.decode(downloaded)
            case let .local(url):
                try await archiveReader.extract(url, archive.kind, entry.path, destination)
                return await Self.decode(destination)
            }
        } catch {
            return nil
        }
    }

    private static func decode(_ url: URL) async -> CGImage? {
        await Task.detached(priority: .utility) {
            defer { try? FileManager.default.removeItem(at: url) }
            return ThumbnailRendering.image(at: url, maxPixel: maxPixel)
        }.value
    }
}
