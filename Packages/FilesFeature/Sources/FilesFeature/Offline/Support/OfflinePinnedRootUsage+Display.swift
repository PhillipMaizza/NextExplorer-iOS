import CoreModels
import FilesClient
import Foundation

extension OfflinePinnedRootUsage {
    /// The last path component, or the whole path for a root without one.
    var displayName: String {
        let last = (root.path as NSString).lastPathComponent
        return last.isEmpty ? root.path : last
    }

    /// The folder holding the pinned item, empty for an item at the top level.
    var parentPath: String {
        (root.path as NSString).deletingLastPathComponent
    }

    /// The file extension, used to pick the file type icon.
    var kind: String {
        (displayName as NSString).pathExtension
    }

    /// The pinned file as its kept copy knows it, for a thumbnail drawn from that copy. Pictures and
    /// videos take the thumbnail path (decoded or framed on the device, the server's otherwise); a PDF
    /// renders its first page from the copy. Nil for a folder.
    var thumbnailFile: FileItem? {
        guard !root.isDirectory else { return nil }
        let kind = kind.lowercased()
        return FileItem(
            name: displayName,
            path: parentPath,
            dateModified: copy?.dateModified ?? .distantPast,
            size: copy?.size ?? sizeBytes,
            kind: kind,
            supportsThumbnail: FileItem.isImageKind(kind) || FileItem.isVideoKind(kind)
        )
    }
}
