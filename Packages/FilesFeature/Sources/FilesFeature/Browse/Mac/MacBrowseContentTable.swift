#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import Foundation
    import SwiftUI

    /// Browse on the Mac: the sortable file table with the saved copy note under it (a table has
    /// no footer row), or while searching, the scope bar over a results table of its own.
    struct MacBrowseContentTable<FileActions: View>: View {
        let store: StoreOf<BrowseFeature>
        let keepsClipboard: Bool
        @Binding var isFilesPickerPresented: Bool
        let onOpen: (FileItem) -> Void
        let onQuickLookUnavailable: (String) -> Void
        @ViewBuilder let fileActions: (FileItem) -> FileActions

        /// The table row standing in for My Files; its id is the `personal` path it opens.
        private static var personalSpaceItem: FileItem {
            FileItem(name: PersonalSpace.rootPath, path: "", dateModified: .distantPast, size: 0, kind: "directory")
        }

        var body: some View {
            if store.isSearching {
                searchContent
                    .transition(.opacity)
            } else {
                VStack(spacing: 0) {
                    table
                    BrowseOfflineFooter(dataSource: store.dataSource)
                }
                .transition(.opacity)
            }
        }

        private var searchContent: some View {
            VStack(spacing: 0) {
                MacSearchScopeBar(
                    availableCategories: store.availableSearchCategories,
                    selectedCategories: store.selectedSearchCategories,
                    onToggle: { store.send(.searchCategoryToggled($0)) },
                    onShowAll: { store.send(.searchFilterCleared) }
                )
                Divider()
                MacSearchResultsTable(
                    sections: store.searchResultSections,
                    favoritePaths: store.favoritePaths,
                    onOpen: { store.send(.searchResultTapped($0)) },
                    onShowInFolder: { store.send(.searchResultEnclosingFolderTapped($0)) }
                )
                if BrowseSearchFooter.isShown(store) {
                    Divider()
                    BrowseSearchFooter(store: store)
                }
            }
            .backgroundGradient()
        }

        private var table: some View {
            MacBrowseTableView(
                items: store.displayedItems,
                sortOption: store.sortOption,
                sortDirection: store.sortDirection,
                onSortChanged: { option, direction in
                    store.send(.sortOptionChanged(option))
                    store.send(.sortDirectionChanged(direction))
                },
                selection: Binding(
                    get: { store.selectedItemIDs },
                    set: { store.send(.tableSelectionChanged($0)) }
                ),
                cutItemIDs: store.clipboard?.operation == .move ? store.clipboard?.sourceItemPaths ?? [] : [],
                offlineItemIDs: store.offlineItemIDs,
                favoriteItemIDs: store.favoritePaths,
                folderSizes: store.folderSizes,
                onOpen: onOpen,
                keyboardActions: BrowseKeyboardActions(
                    store: store,
                    keepsClipboard: keepsClipboard,
                    open: onOpen
                ),
                serverURL: store.serverURL,
                scope: store.cacheScope,
                canDropOnFolders: store.access?.canDelete ?? false,
                onDropOnFolder: { ids, folder in store.send(.itemsDroppedOnFolder(ids: ids, folder: folder)) },
                onDropForeignItemsOnFolder: { items, folder in
                    store.send(.itemsDroppedFromOtherWindow(items, destination: folder.id))
                },
                canUploadToFolders: store.canUploadHere,
                onFilesDroppedOnFolder: { urls, folder in store.send(.filesDroppedOnFolder(urls, folder: folder)) },
                contextMenu: { ids in
                    MacBrowseTableContextMenu(
                        store: store,
                        ids: ids,
                        keepsClipboard: keepsClipboard,
                        isFilesPickerPresented: $isFilesPickerPresented
                    ) { fileActions($0) }
                },
                renamingItemID: store.renamesInTable ? store.renameSheetItem?.id : nil,
                onRenameCommit: { store.send(.renameConfirmed($0)) },
                onRenameCancel: { store.send(.renameCancelled) },
                personalSpace: store.showsPersonalSpace ? Self.personalSpaceItem : nil,
                onOpenPersonalSpace: { store.send(.personalSpaceTapped) },
                onQuickLookUnavailable: onQuickLookUnavailable,
                scrollTargetID: store.scrollTargetID
            )
            .focusedSceneValue(\.browseViewOptions, BrowseViewOptions(
                sortOption: store.sortOption,
                sortDirection: store.sortDirection,
                setSortOption: { store.send(.sortOptionChanged($0)) },
                setSortDirection: { store.send(.sortDirectionChanged($0)) }
            ))
        }
    }

    #Preview("Table") {
        MacBrowseContentTable(
            store: Store(initialState: .preview(items: browsePreviewItems)) { BrowseFeature() },
            keepsClipboard: true,
            isFilesPickerPresented: .constant(false),
            onOpen: { _ in },
            onQuickLookUnavailable: { _ in },
            fileActions: { _ in EmptyView() }
        )
        .frame(width: 640, height: 360)
    }

    #Preview("Searching") {
        MacBrowseContentTable(
            store: Store(initialState: .preview(items: browsePreviewItems, mutate: { $0.searchQuery = "notes" })) {
                BrowseFeature()
            },
            keepsClipboard: true,
            isFilesPickerPresented: .constant(false),
            onOpen: { _ in },
            onQuickLookUnavailable: { _ in },
            fileActions: { _ in EmptyView() }
        )
        .frame(width: 640, height: 360)
    }
#endif
