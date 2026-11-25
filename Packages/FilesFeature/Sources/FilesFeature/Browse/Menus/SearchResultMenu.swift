import CoreModels
import DesignSystem
import Localization
import SwiftUI

/// What a search result offers on a long press (a right click on the Mac), as Finder's search
/// results do: open the hit, show the folder it lives in, copy its path. Browse rows and cells,
/// the Mac results table and Favorites search share it.
struct SearchResultMenu: View {
    let result: SearchResultItem
    let onOpen: () -> Void
    let onShowInFolder: () -> Void

    var body: some View {
        Button(action: onOpen) {
            Label { Text(L10n.Browse.open) } icon: { result.isDirectory ? IconKit.folder : IconKit.document }
        }
        SearchResultLocationMenu(result: result, onShowInFolder: onShowInFolder)
    }
}

struct SearchResultLocationMenu: View {
    let result: SearchResultItem
    let onShowInFolder: () -> Void

    var body: some View {
        Button(action: onShowInFolder) {
            Label { Text(L10n.Browse.showInEnclosingFolder) } icon: { IconKit.folderFill }
        }
        Button { PlatformPasteboard.copy(result.id) } label: {
            Label { Text(L10n.Menu.copyPath) } icon: { IconKit.copy }
        }
    }
}

struct MacSearchHitMenu<FileActions: View>: View {
    let result: SearchResultItem
    let onShowInFolder: () -> Void
    @ViewBuilder let fileActions: () -> FileActions

    var body: some View {
        fileActions()
        Section {
            SearchResultLocationMenu(result: result, onShowInFolder: onShowInFolder)
        }
    }
}

extension SearchResultItem {
    /// The title of the folder the hit lives in: its own name, or the root's for a hit at the top.
    var enclosingFolderTitle: String {
        path.isEmpty ? L10n.Browse.navigationTitle : (path as NSString).lastPathComponent
    }
}

#Preview("File") {
    List {
        SearchResultMenu(
            result: SearchResultItem(name: "budget.xlsx", path: "Documents/Finance", kind: "file"),
            onOpen: {},
            onShowInFolder: {}
        )
    }
}

#Preview("Folder") {
    List {
        SearchResultMenu(
            result: SearchResultItem(name: "Trips", path: "Photos", kind: "dir"),
            onOpen: {},
            onShowInFolder: {}
        )
    }
}
