import CoreModels
import DesignSystem
import Foundation
import Localization

enum FolderContentSummary {
    static func text(folders: Int, files: Int) -> String? {
        switch (folders, files) {
        case (0, 0): nil
        case (_, 0): L10n.Browse.folderCount(folders)
        case (0, _): L10n.Browse.fileCount(files)
        default: L10n.Browse.contentSummary(L10n.Browse.folderCount(folders), L10n.Browse.fileCount(files))
        }
    }

    static func text(for items: some Collection<FileItem>) -> String? {
        let folders = items.count(where: \.isDirectory)
        return text(folders: folders, files: items.count - folders)
    }

    static func crumbs(for directoryPath: String, title: String = "", shareName: String? = nil) -> [PathCrumb] {
        if let root = ReceivedShareSpace.shareRoot(of: directoryPath) {
            let name = shareName ?? (directoryPath == root && !title.isEmpty
                ? title
                : (root as NSString).lastPathComponent)
            let inner = directoryPath.dropFirst(root.count).split(separator: "/").map(String.init)
            return [
                PathCrumb(title: L10n.Shared.sharedWithMe, path: ReceivedShareSpace.rootPath),
                PathCrumb(title: name, path: root),
            ] + inner.indices.map { PathCrumb(title: inner[$0], path: ([root] + inner[...$0]).joined(separator: "/")) }
        }
        let segments = directoryPath.split(separator: "/").map(String.init)
        return segments.indices.map { index in
            PathCrumb(
                title: PersonalSpace.displayName(forSegment: segments[index], isFirstSegment: index == 0),
                path: segments[...index].joined(separator: "/")
            )
        }
    }
}

extension BrowseFeature.State {
    var headerSubtitle: String? {
        #if os(macOS)
            isSearching || directoryPath.isEmpty ? nil : FolderContentSummary.text(for: filteredItems)
        #else
            nil
        #endif
    }

    var headerCrumbs: [PathCrumb] {
        #if os(macOS)
            FolderContentSummary.crumbs(for: directoryPath, title: title, shareName: shareName)
        #else
            []
        #endif
    }
}
