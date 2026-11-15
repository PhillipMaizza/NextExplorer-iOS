#if os(macOS)
    import AppStorageKeys
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import FilesClient
    import Localization
    import SwiftUI

    /// Right click in the table: the clicked rows' actions, or the folder's own (new folder,
    /// upload) on empty space. Paste Here joins every variant while something is staged, so
    /// a full window still has somewhere to paste.
    struct MacBrowseTableContextMenu<RowActions: View>: View {
        let store: StoreOf<BrowseFeature>
        let ids: Set<FileItem.ID>
        let keepsClipboard: Bool
        @Binding var isFilesPickerPresented: Bool
        @ViewBuilder let fileActions: (FileItem) -> RowActions

        var body: some View {
            let items = store.displayedItems.filter { ids.contains($0.id) }
            if items.isEmpty {
                if !store.directoryPath.isEmpty, store.canCreateFolderHere {
                    Button { store.send(.newFolderTapped) } label: {
                        Label { Text(L10n.Browse.actionNewFolder) } icon: { IconKit.folder }
                    }
                    .tint(.primaryDS)
                }
                if !store.directoryPath.isEmpty, store.canCreateFileHere {
                    Button { store.send(.newFileTapped) } label: {
                        Label { Text(L10n.Browse.actionNewFile) } icon: { IconKit.newFile }
                    }
                    .tint(.primaryDS)
                }
                if store.canUploadHere {
                    Button { isFilesPickerPresented = true } label: {
                        Label { Text(L10n.Uploads.actionUploadFromFiles) } icon: { IconKit.upload }
                    }
                    .tint(.primaryDS)
                }
            } else if items.count == 1, let item = items.first {
                fileActions(item)
            } else {
                Section {
                    Button {
                        store.send(.tableSelectionChanged(ids))
                        store.send(.copySelectionTapped, animation: DSMotion.listDiff)
                    } label: {
                        Label { Text(L10n.Browse.actionCopy) } icon: { IconKit.copy }
                    }
                    .tint(.primaryDS)
                    if store.access?.canWrite ?? false, !store.directoryPath.isEmpty {
                        Button {
                            store.send(.tableSelectionChanged(ids))
                            store.send(.duplicateSelectionTapped, animation: DSMotion.listDiff)
                        } label: {
                            Label { Text(L10n.Browse.actionDuplicate) } icon: { IconKit.duplicate }
                        }
                        .tint(.primaryDS)
                    }
                    if store.access?.canWrite ?? false, store.access?.canDelete ?? false {
                        Button {
                            store.send(.tableSelectionChanged(ids))
                            store.send(.cutSelectionTapped, animation: DSMotion.listDiff)
                        } label: {
                            Label { Text(L10n.Browse.actionCut) } icon: { IconKit.cut }
                        }
                        .tint(.primaryDS)
                    }
                    if store.access?.canWrite ?? false, store.access?.canDelete ?? false {
                        Button {
                            store.send(.tableSelectionChanged(ids))
                            store.send(.bulkMoveTapped, animation: DSMotion.listDiff)
                        } label: {
                            Label { Text(L10n.Browse.actionMove) } icon: { IconKit.move }
                        }
                        .tint(.primaryDS)
                    }
                }
                Section {
                    // Select mode's bulk bar is iOS only, so the Mac's several row actions live here.
                    if store.access?.canDownload ?? false {
                        Button {
                            store.send(.tableSelectionChanged(ids))
                            store.send(.bulkDownloadTapped)
                        } label: {
                            Label { Text(L10n.Browse.actionDownload) } icon: { IconKit.download }
                        }
                        .tint(.primaryDS)
                    }
                }
                // Available Offline and Favorites, always their own group; a removal is red.
                Section {
                    if store.access?.canDownload ?? false {
                        let offlineAction = OfflineBulkAction.resolve(
                            selectedIDs: items.map(\.id),
                            offlineIDs: store.offlineItemIDs
                        )
                        RemovableMenuButton(
                            title: offlineAction?.title ?? L10n.Browse.actionAvailableOffline,
                            icon: offlineAction?.icon ?? IconKit.availableOffline,
                            isRemoval: offlineAction == .remove
                        ) {
                            store.send(.tableSelectionChanged(ids))
                            store.send(.bulkOfflineTapped)
                        }
                        .disabled(offlineAction == nil)
                    }
                    if items.allSatisfy(\.isDirectory) {
                        let isAllFavorite = items.allSatisfy { store.favoritePaths.contains($0.id) }
                        RemovableMenuButton(
                            title: isAllFavorite
                                ? L10n.Browse.actionRemoveFromFavorites
                                : L10n.Browse.actionAddToFavorites,
                            icon: isAllFavorite ? IconKit.starFill : IconKit.star,
                            isRemoval: isAllFavorite
                        ) {
                            store.send(.tableSelectionChanged(ids))
                            store.send(.bulkFavoriteTapped)
                        }
                        .disabled(!store.hasLoadedFavorites)
                    }
                }
                Section {
                    if store.access?.canDelete ?? false {
                        Button(role: .destructive) {
                            store.send(.tableSelectionChanged(ids))
                            store.send(.deleteSelectionTapped)
                        } label: {
                            Label { Text(L10n.Browse.actionDelete) } icon: { IconKit.delete }
                        }
                    }
                }
            }
            if store.clipboard != nil, !store.directoryPath.isEmpty {
                Divider()
                BrowsePasteMenu(store: store, keepsClipboard: keepsClipboard)
                    .tint(.primaryDS)
            }
        }
    }

    @MainActor
    extension BrowseKeyboardActions {
        /// The Edit and File menu actions for the table's selection in `store`.
        init(store: StoreOf<BrowseFeature>, keepsClipboard: Bool, open: @escaping (FileItem) -> Void) {
            let canPaste = store.clipboard != nil && !store.directoryPath.isEmpty
            self.init(
                cut: { store.send(.cutSelectionTapped) },
                copy: { store.send(.copySelectionTapped) },
                duplicate: { store.send(.duplicateSelectionTapped, animation: DSMotion.listDiff) },
                undo: { store.send(.undoTapped, animation: DSMotion.listDiff) },
                canUndo: !store.undoStack.isEmpty,
                paste: {
                    guard canPaste else { return }
                    store.send(.pasteTapped(keepItemsAfterCopy: keepsClipboard), animation: DSMotion.listDiff)
                },
                delete: { store.send(.deleteSelectionTapped) },
                rename: { store.send(.renameSelectionTapped) },
                selectAll: { store.send(.tableSelectionChanged(Set(store.displayedItems.map(\.id)))) },
                getInfo: { store.send(.infoSelectionTapped) },
                canPaste: canPaste,
                open: {
                    guard store.selectedItemIDs.count == 1,
                          let item = store.displayedItems.first(where: { store.selectedItemIDs.contains($0.id) })
                    else { return }
                    open(item)
                },
                copyPath: {
                    let paths = store.displayedItems.filter { store.selectedItemIDs.contains($0.id) }.map(\.id)
                    guard !paths.isEmpty else { return }
                    PlatformPasteboard.copy(paths.joined(separator: "\n"))
                }
            )
        }
    }
#endif
