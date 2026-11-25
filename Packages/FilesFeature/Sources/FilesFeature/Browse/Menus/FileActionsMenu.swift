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

    var body: some View {
        #if os(macOS)
            // Finder's context menu starts with Open: the folder, or the in app preview.
            Button {
                store.send(.rowTapped(item))
            } label: {
                Label { Text(L10n.Browse.open) } icon: { item.isDirectory ? IconKit.folder : IconKit.document }
            }
            .tint(.primaryDS)
            .keyboardShortcut("o")
            if item.isDirectory {
                Button {
                    openWindow(value: FolderWindowRoute(path: item.id, title: item.name))
                } label: {
                    Label { Text(L10n.Browse.actionOpenInNewWindow) } icon: { IconKit.newWindow }
                }
                .tint(.primaryDS)
                Divider()
            } else {
                MacOpenWithMenuItems(item: item, serverURL: store.serverURL, onFailure: onOpenWithFailed)
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
            if store.access?.canWrite ?? false {
                Section { archiveActions }
            }
        #elseif os(iOS)
            Section { sendActions }
            Section { keepActions(removals: false) }
        #endif
        Section {
            keepActions(removals: true)
            if store.access?.canDelete ?? false {
                Button(role: .destructive) {
                    store.send(.deleteTapped(item))
                } label: {
                    Label { Text(L10n.Browse.actionDelete).foregroundStyle(Color.negativeText) } icon: { IconKit.delete
                    }
                }
                .tint(.negative)
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
                Label { Text(L10n.Browse.actionGetInfo) } icon: { IconKit.info }
            }
            .tint(.primaryDS)
            .macMenuShortcut("i")
        }
        #if os(macOS)
            renameAction
        #endif
        if !store.shouldShowDeviceContent {
            Button {
                store.send(.permissionsTapped(item))
            } label: {
                Label { Text(L10n.Browse.actionPermissions) } icon: { IconKit.lock }
            }
            .tint(.primaryDS)
        }
        if item.isHTML, !store.shouldShowDeviceContent {
            Button {
                store.send(.openInBrowserTapped(item))
            } label: {
                Label { Text(L10n.Browse.actionOpenInBrowser) } icon: { IconKit.web }
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
                Label { Text(L10n.Browse.actionRefreshSize) } icon: { IconKit.retry }
            }
            .tint(.primaryDS)
        }
        #if os(iOS)
            renameAction
            if store.access?.canWrite ?? false {
                archiveActions
            }
        #endif
        // Copy needs no permission on this folder (the server checks the destination on
        // paste); move has to delete the original, so it mirrors the web client's
        // `canWrite && canDelete` gate. A lone root location has nowhere to go and can't be
        // left absent, so neither is offered for it.
        if !isSoleRootLocation, !store.shouldShowDeviceContent {
            Button {
                store.send(.copyTapped(item), animation: DSMotion.listDiff)
            } label: {
                Label { Text(L10n.Browse.actionCopy) } icon: { IconKit.copy }
            }
            .tint(.primaryDS)
            .macMenuShortcut("c")
            #if os(macOS)
                if store.access?.canWrite ?? false, !store.directoryPath.isEmpty, isInListing {
                    Button {
                        store.send(.tableSelectionChanged([item.id]))
                        store.send(.duplicateSelectionTapped, animation: DSMotion.listDiff)
                    } label: {
                        Label { Text(L10n.Browse.actionDuplicate) } icon: { IconKit.duplicate }
                    }
                    .tint(.primaryDS)
                    .keyboardShortcut("d")
                }
                // Stages the row for a move, as Command X does; Move still opens the picker.
                if store.access?.canWrite ?? false, store.access?.canDelete ?? false, isInListing {
                    Button {
                        store.send(.tableSelectionChanged([item.id]))
                        store.send(.cutSelectionTapped, animation: DSMotion.listDiff)
                    } label: {
                        Label { Text(L10n.Browse.actionCut) } icon: { IconKit.cut }
                    }
                    .tint(.primaryDS)
                    .keyboardShortcut("x")
                }
            #endif
            if store.access?.canWrite ?? false, store.access?.canDelete ?? false {
                Button {
                    store.send(.moveTapped(item), animation: DSMotion.listDiff)
                } label: {
                    Label { Text(L10n.Browse.actionMove) } icon: { IconKit.move }
                }
                .tint(.primaryDS)
            }
        }
    }

    @ViewBuilder
    private var renameAction: some View {
        if store.access?.canWrite ?? false {
            Button {
                store.send(.renameTapped(item))
            } label: {
                Label { Text(L10n.Browse.actionRename) } icon: { IconKit.rename }
            }
            .tint(.primaryDS)
            .macMenuShortcut(.return, modifiers: [])
        }
    }

    @ViewBuilder
    private var archiveActions: some View {
        if store.state.canExtract(item) {
            Button {
                store.send(.extractTapped(item))
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
        if store.access?.canDownload ?? false, SaveActionStyle.isAvailable(for: item.isDirectory),
           !store.shouldShowDeviceContent || (isKept && !Self.shouldSaveKeptCopyLocally)
        {
            Button {
                store.send(.downloadTapped(item))
            } label: {
                Label { Text(SaveActionStyle.title) } icon: { SaveActionStyle.icon }
            }
            .tint(.primaryDS)
        }
        if store.shouldShowDeviceContent {
            if isKept, !item.isDirectory, BrowseFeature.State.canShareKeptFiles {
                Button {
                    store.send(.keptShareTapped([item]))
                } label: {
                    Label { Text(L10n.PreviewToolbar.share) } icon: { IconKit.share }
                }
                .tint(.primaryDS)
            }
        } else if store.access?.canShare ?? false {
            Button {
                onShare(item)
            } label: {
                Label { Text(L10n.Browse.actionShare) } icon: { IconKit.shareLink }
            }
            .tint(.primaryDS)
        }
    }

    /// Available Offline and Favorites. Taking an item off either reads as a removal: red, like Delete.
    @ViewBuilder
    private func keepActions(removals: Bool) -> some View {
        if store.access?.canDownload ?? false, !store.shouldShowDeviceContent || isKept, isKept == removals {
            // A file kept through a pinned folder removes that folder, after a confirmation naming it.
            RemovableMenuButton(
                title: isKept ? L10n.Browse.actionRemoveFromOffline : L10n.Browse.actionAvailableOffline,
                icon: IconKit.availableOffline,
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
                icon: isFavorite ? IconKit.starFill : IconKit.star,
                isRemoval: isFavorite
            ) {
                store.send(.favoriteToggleButtonTapped(item))
            }
            .disabled(!store.hasLoadedFavorites)
        }
    }

    /// A top level location (root screen) that is the only one there: it has nowhere to be
    /// copied or moved to, and can't be left absent, so the transfer actions are hidden.
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

    private var isSoleRootLocation: Bool {
        store.directoryPath.isEmpty && item.path.isEmpty && store.items.count <= 1
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
