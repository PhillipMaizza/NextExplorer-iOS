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
}
