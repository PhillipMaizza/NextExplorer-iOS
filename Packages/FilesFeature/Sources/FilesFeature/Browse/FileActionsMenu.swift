import ComposableArchitecture
import CoreModels
import DesignSystem
import Localization
import SwiftUI
#if os(macOS)
    import AppKit
#endif

/// The `…` / long-press action menu for one file or folder, shared by the Browse list rows and
/// grid cells. Sends straight into `BrowseFeature`; the one piece of view-local state it can't
/// own (the share sheet target) is handed back through `onShare`.
struct FileActionsMenu: View {
    let store: StoreOf<BrowseFeature>
    let item: FileItem
    let removeArchiveAfterDownload: Bool
    let onShare: (FileItem) -> Void

    #if os(macOS)
        @Environment(\.openWindow) private var openWindow
    #endif

    var body: some View {
        #if os(macOS)
            if item.isDirectory {
                Button {
                    openWindow(value: FolderWindowRoute(path: item.id, title: item.name))
                } label: {
                    Label { Text(L10n.Browse.actionOpenInNewWindow) } icon: { IconKit.newWindow }
                }
                .tint(.primaryDS)
                Button {
                    openWindow(value: FolderWindowRoute(path: item.id, title: item.name, tabHostWindowNumber: NSApp.keyWindow?.windowNumber))
                } label: {
                    Label { Text(L10n.Browse.actionOpenInNewTab) } icon: { IconKit.newTab }
                }
                .tint(.primaryDS)
                Divider()
            }
        #endif
        // Explicit `.tint`: the Browse tree runs under `.tint(Color.accent)`, which would
        // otherwise cascade into the menu and color every icon/label gold instead of the
        // system's normal label color — only Delete should stand out, in red.
        Button {
            store.send(.infoTapped(item))
        } label: {
            Label { Text(L10n.Browse.actionGetInfo) } icon: { IconKit.info }
        }
        .tint(.primaryDS)
        Button {
            store.send(.permissionsTapped(item))
        } label: {
            Label { Text(L10n.Browse.actionPermissions) } icon: { IconKit.lock }
        }
        .tint(.primaryDS)
        if item.isHTML {
            Button {
                store.send(.openInBrowserTapped(item))
            } label: {
                Label { Text(L10n.Browse.actionOpenInBrowser) } icon: { IconKit.web }
            }
            .tint(.primaryDS)
        }
        if store.access?.canWrite ?? false {
            Button {
                store.send(.renameTapped(item))
            } label: {
                Label { Text(L10n.Browse.actionRename) } icon: { IconKit.rename }
            }
            .tint(.primaryDS)
        }
        if store.access?.canWrite ?? false {
            // Extract only offers `.zip` — the server's own extract route 415s anything else
            // ("Only .zip archives are supported"), `.rar` included despite this app being
            // able to browse rar contents client-side.
            if item.kind.lowercased() == "zip" {
                Button {
                    store.send(.extractZipTapped(item))
                } label: {
                    Label { Text(L10n.Browse.actionExtract) } icon: { IconKit.extract }
                }
                .tint(.primaryDS)
            }
            Button {
                store.send(.compressTapped(item))
            } label: {
                Label { Text(L10n.Browse.actionCompress) } icon: { IconKit.archiveDocument }
            }
            .tint(.primaryDS)
        }
        // Copy needs no permission on this folder (the server checks the destination on
        // paste); move has to delete the original, so it mirrors the web client's
        // `canWrite && canDelete` gate. A lone root location has nowhere to go and can't be
        // left absent, so neither is offered for it.
        if !isSoleRootLocation {
            Button {
                store.send(.copyTapped(item), animation: .default)
            } label: {
                Label { Text(L10n.Browse.actionCopy) } icon: { IconKit.copy }
            }
            .tint(.primaryDS)
            if store.access?.canWrite ?? false, store.access?.canDelete ?? false {
                Button {
                    store.send(.moveTapped(item), animation: .default)
                } label: {
                    Label { Text(L10n.Browse.actionMove) } icon: { IconKit.move }
                }
                .tint(.primaryDS)
            }
        }
        if store.access?.canDownload ?? false {
            Button {
                store.send(.downloadTapped(item, .documents, removeArchiveAfterDownload: removeArchiveAfterDownload))
            } label: {
                Label { Text(L10n.Browse.actionDownload) } icon: { IconKit.download }
            }
            .tint(.primaryDS)
        }
        // Only folders can be favorited — the server 400s on anything else.
        if item.isDirectory {
            Button {
                store.send(.favoriteToggleButtonTapped(item))
            } label: {
                if store.favoritePaths.contains(item.id) {
                    Label { Text(L10n.Browse.actionRemoveFromFavorites) } icon: { IconKit.starFill }
                } else {
                    Label { Text(L10n.Browse.actionAddToFavorites) } icon: { IconKit.star }
                }
            }
            .tint(.primaryDS)
        }
        if store.access?.canShare ?? false {
            Button {
                onShare(item)
            } label: {
                Label { Text(L10n.Browse.actionShare) } icon: { IconKit.shareLink }
            }
            .tint(.primaryDS)
        }
        if store.access?.canDelete ?? false {
            Button(role: .destructive) {
                store.send(.deleteTapped(item))
            } label: {
                Label { Text(L10n.Browse.actionDelete) } icon: { IconKit.delete }
            }
            .tint(.negative)
        }
    }

    /// A top-level location (root screen) that is the only one there: it has nowhere to be
    /// copied or moved to, and can't be left absent, so the transfer actions are hidden.
    private var isSoleRootLocation: Bool {
        store.directoryPath.isEmpty && item.path.isEmpty && store.items.count <= 1
    }
}
