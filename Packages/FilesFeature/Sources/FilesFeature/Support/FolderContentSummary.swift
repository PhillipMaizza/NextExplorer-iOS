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
            PathCrumb.trail(for: directoryPath, title: title, shareName: shareName)
        #else
            []
        #endif
    }
}
