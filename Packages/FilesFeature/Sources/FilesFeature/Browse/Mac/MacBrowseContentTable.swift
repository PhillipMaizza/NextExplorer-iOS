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
        let shouldKeepClipboard: Bool
        @Binding var isFilesPickerPresented: Bool
        let onOpen: (FileItem) -> Void
        @Binding var isPeeking: Bool
        @ViewBuilder let fileActions: (FileItem) -> FileActions

        /// The table row standing in for My Files; its id is the `personal` path it opens.
        private static var personalSpaceItem: FileItem {
            FileItem(name: PersonalSpace.rootPath, path: "", dateModified: .distantPast, size: 0, kind: "directory")
        }

        var body: some View {
            if store.isShowingElsewhereResults {
                MacElsewhereResults(store: store, fileActions: hitActions)
                    .transition(.opacity)
            } else if store.isSearching {
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
                    counts: store.searchCategoryCounts,
                    selectedCategories: store.selectedSearchCategories,
                    onToggle: { store.send(.searchCategoryToggled($0)) },
                    onShowAll: { store.send(.searchFilterCleared) }
                )
                MacSearchResultsTable(
                    sections: store.searchResultSections,
                    favoritePaths: store.favoritePaths,
                    serverURL: store.preferences.shouldShowThumbnails ? store.serverURL : nil,
                    onOpen: { store.send(.searchResultTapped($0)) },
                    fileActions: hitActions
                )
                if BrowseSearchFooter.isShown(store) {
                    Divider()
                    BrowseSearchFooter(store: store)
                }
            }
            .backgroundGradient()
        }

        private func hitActions(_ result: SearchResultItem) -> some View {
            MacSearchHitMenu(
                result: result,
                onShowInFolder: { store.send(.searchResultEnclosingFolderTapped(result)) },
                fileActions: { fileActions(result.actionItem) }
            )
        }

        private var table: some View {
            MacBrowseTableView(
                items: store.displayedItems,
                sortOption: store.sortOption,
                sortDirection: store.sortDirection,
                onSortChanged: { store.send(.sortChanged($0, $1)) },
                selection: Binding(
                    get: { store.selectedItemIDs },
                    set: { store.send(.tableSelectionChanged($0)) }
                ),
                cutItemIDs: store.clipboard?.operation == .move ? store.clipboard?.sourceItemPaths ?? [] : [],
                offlineItemIDs: store.offlineItemIDs,
                favoriteItemIDs: store.favoritePaths,
                folderSizes: store.folderSizes,
                shouldShowThumbnails: store.preferences.shouldShowThumbnails,
                onOpen: onOpen,
                keyboardActions: BrowseKeyboardActions(
                    store: store,
                    shouldKeepClipboard: shouldKeepClipboard,
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
                        shouldKeepClipboard: shouldKeepClipboard,
                        isFilesPickerPresented: $isFilesPickerPresented
                    ) { fileActions($0) }
                },
                renamingItemID: store.shouldRenameInTable ? store.renameSheetItem?.id : nil,
                onRenameCommit: { store.send(.renameConfirmed($0)) },
                onRenameCancel: { store.send(.renameCancelled) },
                personalSpace: store.shouldShowPersonalSpace ? Self.personalSpaceItem : nil,
                onOpenPersonalSpace: { store.send(.personalSpaceTapped) },
                isPeeking: isPeeking,
                onPeek: { isPeeking = true },
                scrollTargetID: store.scrollTargetID,
                onScrollTargetShown: { store.send(.scrollTargetShown) }
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
            shouldKeepClipboard: true,
            isFilesPickerPresented: .constant(false),
            onOpen: { _ in },
            isPeeking: .constant(false),
            fileActions: { _ in EmptyView() }
        )
        .frame(width: 640, height: 360)
    }

    #Preview("Searching") {
        MacBrowseContentTable(
            store: Store(initialState: .preview(items: browsePreviewItems, mutate: { $0.searchQuery = "notes" })) {
                BrowseFeature()
            },
            shouldKeepClipboard: true,
            isFilesPickerPresented: .constant(false),
            onOpen: { _ in },
            isPeeking: .constant(false),
            fileActions: { _ in EmptyView() }
        )
        .frame(width: 640, height: 360)
    }
#endif
