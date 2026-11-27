import ComposableArchitecture
import CoreModels
import DesignSystem
import FilesClient
import Localization
import SwiftUI
#if os(macOS)
    import AppKit
#endif

/// The `…` / long press action menu for one file or folder, shared by the Browse list rows and
/// grid cells. Sends straight into `BrowseFeature`; the one piece of view local state it can't
/// own (the share sheet target) is handed back through `onShare`.
struct FileActionsMenu: View {
    let store: StoreOf<BrowseFeature>
    let item: FileItem
    let onShare: (FileItem) -> Void
    /// Where a failed Mac "Open With" reports, since the menu has closed by then.
    var onOpenWithFailed: (String) -> Void = { _ in }

    #if os(macOS)
        @Environment(\.openWindow) private var openWindow
        @Dependency(\.offlineFileStore) private var offlineFileStore
    #endif

    private var actions: FileItemActions {
        store.state.actions(for: item)
    }

    var body: some View {
        #if os(macOS)
            // Finder's context menu starts with Open: the folder, or the in app preview.
            Button {
                store.send(.rowTapped(item))
            } label: {
                Label { Text(L10n.Browse.open) } icon: { MenuIcon.open(isDirectory: item.isDirectory).image }
            }
            .tint(.primaryDS)
            .keyboardShortcut("o")
            if item.isDirectory {
                Button {
                    openWindow(value: FolderWindowRoute(path: item.id, title: item.name))
                } label: {
                    Label { Text(L10n.Browse.actionOpenInNewWindow) } icon: { MenuIcon.newWindow.image }
                }
                .tint(.primaryDS)
                Divider()
            } else {
                if actions.canExport {
                    MacOpenWithMenuItems(item: item, serverURL: store.serverURL, onFailure: onOpenWithFailed)
                }
                Divider()
            }
        #endif
        // Explicit `.tint`: the Browse tree runs under `.tint(Color.accent)`, which would
        // otherwise cascade into the menu and color every icon/label gold instead of the
        // system's normal label color: only removals and Delete stand out, in red.
        // Device content offers only actions on kept files.
        Section { aboutActions }
        Section { editActions }
        #if os(macOS)
            Section {
                sendActions
                keepActions(removals: false)
            }
            if actions.canCompress {
                Section { archiveActions }
            }
        #elseif os(iOS)
            Section { sendActions }
            Section { keepActions(removals: false) }
        #endif
        Section {
            keepActions(removals: true)
            if actions.canDelete {
                RemovableMenuButton(title: L10n.Browse.actionDelete, icon: MenuIcon.delete.image, isRemoval: true) {
                    store.send(.deleteTapped(item))
                }
                .macMenuShortcut(.delete)
            }
        }
    }

    @ViewBuilder
    private var aboutActions: some View {
        if isGetInfoAvailable, !store.shouldShowDeviceContent {
            Button {
                store.send(.infoTapped(item))
            } label: {
                Label { Text(L10n.Browse.actionGetInfo) } icon: { MenuIcon.getInfo.image }
            }
            .tint(.primaryDS)
            .macMenuShortcut("i")
            #if os(macOS)
                MacVersionsMenu(store: store, item: item)
                    .tint(.primaryDS)
            #endif
        }
        #if os(macOS)
            renameAction
        #endif
        if actions.canEditPermissions {
            Button {
                store.send(.permissionsTapped(item))
            } label: {
                Label { Text(L10n.Browse.actionPermissions) } icon: { MenuIcon.permissions.image }
            }
            .tint(.primaryDS)
        }
        if item.isHTML, !store.shouldShowDeviceContent {
            Button {
                store.send(.openInBrowserTapped(item))
            } label: {
                Label { Text(L10n.Browse.actionOpenInBrowser) } icon: { MenuIcon.openInBrowser.image }
            }
            .tint(.primaryDS)
        }
    }

    @ViewBuilder
    private var editActions: some View {
        if item.isDirectory, store.folderSizeMode != .off {
            Button {
                store.send(.folderSizeRefreshTapped(item.id))
            } label: {
                Label { Text(L10n.Browse.actionRefreshSize) } icon: { MenuIcon.refresh.image }
            }
            .tint(.primaryDS)
        }
        #if os(iOS)
            renameAction
            if actions.canCompress {
                archiveActions
            }
        #endif
        if actions.canCopy {
            Button {
                store.send(.copyTapped(item), animation: DSMotion.listDiff)
            } label: {
                Label { Text(L10n.Browse.actionCopy) } icon: { MenuIcon.copy.image }
            }
            .tint(.primaryDS)
            .macMenuShortcut("c")
            #if os(macOS)
                if actions.canDuplicate {
                    Button {
                        store.send(.tableSelectionChanged([item.id]))
                        store.send(.duplicateSelectionTapped, animation: DSMotion.listDiff)
                    } label: {
                        Label { Text(L10n.Browse.actionDuplicate) } icon: { MenuIcon.duplicate.image }
                    }
                    .tint(.primaryDS)
                    .keyboardShortcut("d")
                }
                if actions.canMove, isInListing {
                    Button {
                        store.send(.tableSelectionChanged([item.id]))
                        store.send(.cutSelectionTapped, animation: DSMotion.listDiff)
                    } label: {
                        Label { Text(L10n.Browse.actionCut) } icon: { MenuIcon.cut.image }
                    }
                    .tint(.primaryDS)
                    .keyboardShortcut("x")
                }
            #endif
            if actions.canMove {
                Button {
                    store.send(.moveTapped(item), animation: DSMotion.listDiff)
                } label: {
                    Label { Text(MoveActionStyle.title) } icon: { MenuIcon.move.image }
                }
                .tint(.primaryDS)
            }
            #if os(macOS)
                Button {
                    store.send(.copyToTapped(item))
                } label: {
                    Label { Text(L10n.Browse.actionCopyTo) } icon: { MenuIcon.copyTo.image }
                }
                .tint(.primaryDS)
            #endif
        }
    }

    @ViewBuilder
    private var renameAction: some View {
        if actions.canRename {
            Button {
                store.send(.renameTapped(item))
            } label: {
                Label { Text(L10n.Browse.actionRename) } icon: { MenuIcon.rename.image }
            }
            .tint(.primaryDS)
        }
    }

    @ViewBuilder
    private var archiveActions: some View {
        if actions.canExtract {
            Button {
                store.send(.extractTapped(item))
            } label: {
                Label { Text(L10n.Browse.actionExtract) } icon: { MenuIcon.extract.image }
            }
            .tint(.primaryDS)
            Button {
                store.send(.extractHereTapped(item))
            } label: {
                Label { Text(L10n.Browse.actionExtractHere) } icon: { MenuIcon.extract.image }
            }
            .tint(.primaryDS)
        }
        Button {
            store.send(.compressTapped(item))
        } label: {
            Label { Text(L10n.Browse.actionCompress) } icon: { MenuIcon.compress.image }
        }
        .tint(.primaryDS)
    }

    private static var shouldSaveKeptCopyLocally: Bool {
        #if os(macOS)
            true
        #elseif os(iOS)
            false
        #endif
    }

    /// On device content only a kept file can be saved or shared, from its copy on the device.
    private var isKept: Bool {
        store.offlineItemIDs.contains(item.id) || store.searchOnDeviceIDs.contains(item.id)
    }

    @ViewBuilder
    private var sendActions: some View {
        #if os(macOS)
            if store.shouldShowDeviceContent, isKept, !item.isDirectory {
                MacLocalFileMenuItems(
                    resolve: offlineFileStore.pinned(to: store.cacheScope).keptCopy(of: item)
                )
            }
        #endif
        if actions.canDownload, SaveActionStyle.isAvailable(for: item.isDirectory),
           !store.shouldShowDeviceContent || (isKept && !Self.shouldSaveKeptCopyLocally)
        {
            Button {
                store.send(.downloadTapped(item))
            } label: {
                Label { Text(SaveActionStyle.title) } icon: { MenuIcon.download.image }
            }
            .tint(.primaryDS)
        }
        if store.shouldShowDeviceContent {
            if isKept, !item.isDirectory, BrowseFeature.State.canShareKeptFiles {
                Button {
                    store.send(.keptShareTapped([item]))
                } label: {
                    Label { Text(L10n.PreviewToolbar.share) } icon: { MenuIcon.systemShare.image }
                }
                .tint(.primaryDS)
            }
        } else if actions.canShare {
            Button {
                onShare(item)
            } label: {
                Label { Text(L10n.Browse.actionShare) } icon: { MenuIcon.shareLink.image }
            }
            .tint(.primaryDS)
        }
    }

    /// Available Offline and Favorites. Taking an item off either reads as a removal: red, like Delete.
    @ViewBuilder
    private func keepActions(removals: Bool) -> some View {
        if isKept == removals, isKept || actions.canKeepOffline {
            // A file kept through a pinned folder removes that folder, after a confirmation naming it.
            RemovableMenuButton(
                title: isKept ? L10n.Browse.actionRemoveFromOffline : L10n.Browse.actionAvailableOffline,
                icon: MenuIcon.keepOffline.image,
                isRemoval: isKept
            ) {
                store.send(.offlineToggleTapped(item))
            }
        }
        // Only folders can be favorited: the server 400s on anything else.
        if item.isDirectory, !store.shouldShowDeviceContent, store.favoritePaths.contains(item.id) == removals {
            let isFavorite = removals
            RemovableMenuButton(
                title: isFavorite ? L10n.Browse.actionRemoveFromFavorites : L10n.Browse.actionAddToFavorites,
                icon: MenuIcon.favorite(isOn: isFavorite).image,
                isRemoval: isFavorite
            ) {
                store.send(.favoriteToggleButtonTapped(item))
            }
            .disabled(!store.hasLoadedFavorites)
        }
    }

    private var isInListing: Bool {
        store.items[id: item.id] != nil
    }

    private var isGetInfoAvailable: Bool {
        #if os(macOS)
            !store.directoryPath.isEmpty || !isInListing
        #elseif os(iOS)
            true
        #endif
    }
}

@MainActor
private enum PreviewSample {
    static let folder = FileItem(
        name: "Projects",
        path: "",
        dateModified: .distantPast,
        size: 0,
        kind: FileItem.directoryKind
    )

    /// A folder kept offline and in the favorites, so the last group shows both removals in red.
    static func menu() -> some View {
        var state = BrowseFeature.State(
            serverURL: URL(fileURLWithPath: "/"),
            directoryPath: "",
            title: "Files"
        )
        state.offlineItemIDs = [folder.id]
        state.offlinePinnedItemIDs = [folder.id]
        state.favoritePaths = [folder.id]
        return Menu("Projects") {
            FileActionsMenu(store: Store(initialState: state) { BrowseFeature() }, item: folder, onShare: { _ in })
        }
        .padding()
        .background(Color.backgroundPrimary)
    }
}

#Preview("Folder kept offline and favorited") {
    PreviewSample.menu()
}

private extension View {
    func macMenuShortcut(_ key: KeyEquivalent, modifiers: EventModifiers = .command) -> some View {
        #if os(macOS)
            keyboardShortcut(key, modifiers: modifiers)
        #elseif os(iOS)
            self
        #endif
    }
}
