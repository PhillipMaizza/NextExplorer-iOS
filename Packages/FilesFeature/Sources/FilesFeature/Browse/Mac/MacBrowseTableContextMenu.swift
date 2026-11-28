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
        let shouldKeepClipboard: Bool
        @Binding var isFilesPickerPresented: Bool
        @ViewBuilder let fileActions: (FileItem) -> RowActions

        var body: some View {
            let items = store.displayedItems.filter { ids.contains($0.id) }
            if items.isEmpty {
                if !store.shouldShowDeviceContent, let folder = store.state.folderItem(now: .now) {
                    folderActions(folder)
                }
                if !store.directoryPath.isEmpty, store.canCreateFolderHere {
                    Button { store.send(.newFolderTapped) } label: {
                        Label { Text(L10n.Browse.actionNewFolder) } icon: { MenuIcon.newFolder.image }
                    }
                    .tint(.primaryDS)
                    .keyboardShortcut(BrowseShortcut.newFolder)
                }
                if !store.directoryPath.isEmpty, store.canCreateFileHere {
                    Button { store.send(.newFileTapped) } label: {
                        Label { Text(L10n.Browse.actionNewFile) } icon: { MenuIcon.newFile.image }
                    }
                    .tint(.primaryDS)
                    .keyboardShortcut(BrowseShortcut.newFile)
                }
                if store.canUploadHere {
                    Button { isFilesPickerPresented = true } label: {
                        Label { Text(L10n.Uploads.actionUploadFromFiles) } icon: { MenuIcon.upload.image }
                    }
                    .tint(.primaryDS)
                }
            } else if items.count == 1, let item = items.first {
                fileActions(item)
                if item.isDirectory, store.state.canPaste(into: item.id) {
                    Button {
                        store.send(
                            .pasteIntoTapped(item, keepItemsAfterCopy: shouldKeepClipboard),
                            animation: DSMotion.listDiff
                        )
                    } label: {
                        Label { Text(L10n.Browse.actionPasteIntoFolder) } icon: { MenuIcon.paste.image }
                    }
                    .tint(.primaryDS)
                }
            } else {
                Section {
                    if actions(items).canCopy {
                        Button {
                            store.send(.tableSelectionChanged(ids))
                            store.send(.copySelectionTapped, animation: DSMotion.listDiff)
                        } label: {
                            Label { Text(L10n.Browse.actionCopy) } icon: { MenuIcon.copy.image }
                        }
                        .tint(.primaryDS)
                        .keyboardShortcut("c")
                    }
                    if actions(items).canDuplicate {
                        Button {
                            store.send(.tableSelectionChanged(ids))
                            store.send(.duplicateSelectionTapped, animation: DSMotion.listDiff)
                        } label: {
                            Label { Text(L10n.Browse.actionDuplicate) } icon: { MenuIcon.duplicate.image }
                        }
                        .tint(.primaryDS)
                        .keyboardShortcut("d")
                    }
                    if actions(items).canMove {
                        Button {
                            store.send(.tableSelectionChanged(ids))
                            store.send(.cutSelectionTapped, animation: DSMotion.listDiff)
                        } label: {
                            Label { Text(L10n.Browse.actionCut) } icon: { MenuIcon.cut.image }
                        }
                        .tint(.primaryDS)
                        .keyboardShortcut("x")
                    }
                    if actions(items).canMove {
                        Button {
                            store.send(.tableSelectionChanged(ids))
                            store.send(.bulkMoveTapped, animation: DSMotion.listDiff)
                        } label: {
                            Label { Text(L10n.Browse.actionMoveTo) } icon: { MenuIcon.move.image }
                        }
                        .tint(.primaryDS)
                    }
                    if actions(items).canCopy {
                        Button {
                            store.send(.tableSelectionChanged(ids))
                            store.send(.copySelectionToTapped)
                        } label: {
                            Label { Text(L10n.Browse.actionCopyTo) } icon: { MenuIcon.copyTo.image }
                        }
                        .tint(.primaryDS)
                    }
                    if actions(items).canCompress {
                        Button {
                            store.send(.tableSelectionChanged(ids))
                            store.send(.compressSelectionTapped)
                        } label: {
                            Label { Text(L10n.Browse.actionCompress) } icon: { MenuIcon.compress.image }
                        }
                        .tint(.primaryDS)
                    }
                }
                Section {
                    // Select mode's bulk bar is iOS only, so the Mac's several row actions live here.
                    if actions(items).canDownload {
                        Button {
                            store.send(.tableSelectionChanged(ids))
                            store.send(.bulkDownloadTapped)
                        } label: {
                            Label { Text(L10n.Browse.actionDownload) } icon: { MenuIcon.download.image }
                        }
                        .tint(.primaryDS)
                    }
                    offlineAction(items, removals: false)
                    favoriteAction(items, removals: false)
                }
                Section {
                    offlineAction(items, removals: true)
                    favoriteAction(items, removals: true)
                    if actions(items).canDelete {
                        RemovableMenuButton(
                            title: L10n.Browse.actionDelete,
                            icon: MenuIcon.delete.image,
                            isRemoval: true
                        ) {
                            store.send(.tableSelectionChanged(ids))
                            store.send(.deleteSelectionTapped)
                        }
                        .keyboardShortcut(.delete)
                    }
                }
            }
            if store.clipboard != nil, !store.directoryPath.isEmpty {
                Divider()
                BrowsePasteMenu(store: store, shouldKeepClipboard: shouldKeepClipboard)
                    .tint(.primaryDS)
            }
        }

        @ViewBuilder
        private func folderActions(_ folder: FileItem) -> some View {
            Section {
                Button { store.send(.infoTapped(folder)) } label: {
                    Label { Text(L10n.Browse.actionGetInfo) } icon: { MenuIcon.getInfo.image }
                }
                .tint(.primaryDS)
            }
            Section {
                let isFavorite = store.favoritePaths.contains(folder.id)
                RemovableMenuButton(
                    title: isFavorite ? L10n.Browse.actionRemoveFromFavorites : L10n.Browse.actionAddToFavorites,
                    icon: MenuIcon.favorite(isOn: isFavorite).image,
                    isRemoval: isFavorite
                ) {
                    store.send(.favoriteToggleButtonTapped(folder))
                }
                .disabled(!store.hasLoadedFavorites)
            }
        }

        private func actions(_ items: some Collection<FileItem>) -> FileItemActions {
            store.state.actions(for: Array(items))
        }

        @ViewBuilder
        private func offlineAction(_ items: some Collection<FileItem>, removals: Bool) -> some View {
            let action = OfflineBulkAction.resolve(selectedIDs: items.map(\.id), offlineIDs: store.offlineItemIDs)
            if action == .remove || actions(items).canKeepOffline, (action == .remove) == removals {
                RemovableMenuButton(
                    title: action?.title ?? L10n.Browse.actionAvailableOffline,
                    icon: action?.icon ?? MenuIcon.keepOffline.image,
                    isRemoval: removals
                ) {
                    store.send(.tableSelectionChanged(ids))
                    store.send(.bulkOfflineTapped)
                }
                .disabled(action == nil)
            }
        }

        @ViewBuilder
        private func favoriteAction(_ items: some Collection<FileItem>, removals: Bool) -> some View {
            let isAllFavorite = items.allSatisfy { store.favoritePaths.contains($0.id) }
            if items.allSatisfy(\.isDirectory), isAllFavorite == removals {
                RemovableMenuButton(
                    title: removals ? L10n.Browse.actionRemoveFromFavorites : L10n.Browse.actionAddToFavorites,
                    icon: MenuIcon.favorite(isOn: removals).image,
                    isRemoval: removals
                ) {
                    store.send(.tableSelectionChanged(ids))
                    store.send(.bulkFavoriteTapped)
                }
                .disabled(!store.hasLoadedFavorites)
            }
        }
    }

    @MainActor
    extension BrowseKeyboardActions {
        /// The Edit and File menu actions for the table's selection in `store`.
        init(store: StoreOf<BrowseFeature>, shouldKeepClipboard: Bool, open: @escaping (FileItem) -> Void) {
            let canPaste = store.clipboard != nil && !store.directoryPath.isEmpty
            let selected = store.state.actions(for: store.selectedItems)
            self.init(
                cut: { store.send(.cutSelectionTapped) },
                copy: { store.send(.copySelectionTapped) },
                duplicate: { store.send(.duplicateSelectionTapped, animation: DSMotion.listDiff) },
                undo: { store.send(.undoTapped, animation: DSMotion.listDiff) },
                paste: {
                    guard canPaste else { return }
                    store.send(.pasteTapped(keepItemsAfterCopy: shouldKeepClipboard), animation: DSMotion.listDiff)
                },
                delete: { store.send(.deleteSelectionTapped) },
                rename: { store.send(.renameSelectionTapped) },
                selectAll: { store.send(.tableSelectionChanged(Set(store.displayedItems.map(\.id)))) },
                getInfo: { store.send(.infoSelectionTapped) },
                canPaste: canPaste,
                open: {
                    if store.isPersonalSpaceSelected {
                        store.send(.personalSpaceTapped)
                        return
                    }
                    guard let item = store.singleSelectedItem else { return }
                    open(item)
                },
                copyPath: {
                    let paths = store.displayedItems.filter { store.selectedItemIDs.contains($0.id) }.map(\.id)
                    guard !paths.isEmpty else { return }
                    PlatformPasteboard.copy(paths.joined(separator: "\n"))
                },
                redo: { store.send(.redoTapped, animation: DSMotion.listDiff) },
                canCut: selected.canMove,
                canDelete: selected.canDelete,
                canDuplicate: selected.canDuplicate,
                canOpen: store.isPersonalSpaceSelected || store.singleSelectedItem != nil,
                canUndo: !store.undoStack.isEmpty,
                canRedo: !store.redoStack.isEmpty
            )
        }
    }
#endif
