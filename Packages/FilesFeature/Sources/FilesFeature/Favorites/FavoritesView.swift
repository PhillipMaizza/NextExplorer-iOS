import AppStorageKeys
import ComposableArchitecture
import CoreModels
import DesignSystem
import Localization
import SwiftUI

struct FavoritesView: View {
    @Bindable var store: StoreOf<FavoritesFeature>
    /// One list or grid choice for Browse, Favorites and Offline, so switching it in one is switching it everywhere.
    @AppStorage(AppStorageKeys.browseViewMode) private var viewModeRaw = FileListViewMode.list.rawValue
    @AppStorage(AppStorageKeys.thumbnailSize) private var thumbnailSizeRaw = ThumbnailSize.medium.rawValue

    private var thumbnailSize: ThumbnailSize {
        ThumbnailSize(rawValue: thumbnailSizeRaw) ?? .medium
    }

    /// How far the list is pulled below rest, fed to the empty/error overlay so it follows the
    /// pull-to-refresh rubber-band instead of staying pinned.
    @State private var pullOffset: CGFloat = 0

    private var viewMode: FileListViewMode {
        #if os(macOS)
            .list
        #else
            FileListViewMode(rawValue: viewModeRaw) ?? .list
        #endif
    }

    /// The Mac lists favorites as a table once they load; the skeleton list stands in before.
    private var isMacTable: Bool {
        #if os(macOS)
            listPhase != .loading
        #else
            false
        #endif
    }

    private var isAllSelected: Bool {
        !store.displayedFavorites.isEmpty && store.selectedFavoriteIDs.count == store.displayedFavorites.count
    }

    /// The one screen state, derived from the store: skeleton until the first response lands
    /// (`store.phase`), then error / empty / no-results / the list. `phase.errorMessage` is
    /// non nil only on a first load failure with nothing to show, so it needs no empty guard.
    private var listPhase: ListPhase {
        // The favorites list's own error / loading / empty precedence comes first (same shape as
        // every tab). Only once that resolves to `.content` while a query is active does the
        // screen follow the recursive-search sub-machine instead: it shows file results across the
        // favorited folders, keyed off `searchPhase`/results rather than the favorites list.
        let base = ListPhase.derive(
            hasError: store.errorMessage != nil,
            hasLoaded: store.phase.hasLoaded,
            isEmpty: store.favorites.isEmpty,
            hasNoResults: store.hasNoMatchingFavorites
        )
        guard base == .content, store.isSearching else { return base }
        if store.searchPhase.errorMessage != nil, store.fileSearchResults == nil {
            return .error
        }
        if !store.searchPhase.hasLoaded, store.fileSearchResults == nil {
            return .loading
        }
        return store.displayedSearchResults.isEmpty ? .noResults : .content
    }

    /// The message the error overlay shows: the search failure while searching, otherwise the
    /// favorites load failure.
    private var overlayErrorMessage: String? {
        store.isSearching ? store.searchPhase.errorMessage : store.errorMessage
    }

    private var bulkRemoveConfirmationBinding: Binding<Bool> {
        // No op setter: the sheet is dismiss disabled and only closes through `DSAlertSheet`'s
        // own buttons, each driving the reducer directly.
        Binding(get: { store.bulkRemoveConfirmationIsPresented }, set: { _ in })
    }

    private var bulkRemoveConfirmationTitle: String {
        L10n.Favorites.removeConfirm(store.selectedFavoriteIDs.count)
    }

    /// The folder path bar is `SplitDetailBreadcrumb`, floating over the split view: an iPhone
    /// shows none.
    var body: some View {
        NavigationStack(path: $store.scope(state: \.path, action: \.path)) {
            rootContent
        } destination: { store in
            BrowseContentView(store: store)
        }
        .platformAccentTint()
    }

    private var rootContent: some View {
        Group {
            if store.isSearching {
                FavoritesSearchResultsList(store: store, phase: listPhase, pullOffset: $pullOffset)
            } else if isMacTable {
                #if os(macOS)
                    MacFavoritesTableView(store: store, favorites: store.displayedFavorites)
                        .backgroundGradient()
                        .transition(.opacity)
                #endif
            } else if viewMode == .list {
                listContent
            } else {
                gridContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .top, spacing: 0) {
            PinnedTitleSearchHeader(
                title: L10n.Favorites.navigationTitle,
                selectionTitle: store.isSelecting ? L10n.Common.selectedCount(store.selectedFavoriteIDs.count) : nil,
                searchText: $store.searchQuery.sending(\.searchQueryChanged),
                shouldFadeIntoContent: !isMacTable,
                isSearchPending: store.isSearchPending
            )
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                if store.isSearchTermTooShort {
                    SearchStatusFooter(message: SearchStatusFooter.tooShortMessage, canShowMore: false, onShowMore: {})
                        .background(Color.backgroundPrimary, ignoresSafeAreaEdges: .bottom)
                        .transition(.opacity)
                }
                if case let .cached(fetchedAt) = store.dataSource {
                    DSInfoCard(L10n.Browse.offlineBannerDetail(OfflineRelativeTime.string(from: fetchedAt)))
                        .padding(.horizontal, .space16)
                        .padding(.vertical, .space8)
                        .background(Color.backgroundPrimary, ignoresSafeAreaEdges: .bottom)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: store.dataSource)
        .animation(.easeInOut(duration: 0.2), value: store.isSearchTermTooShort)
        .syncRefreshFeedback(errorMessage: store.errorMessage) {
            await store.send(.refreshButtonTapped).finish()
        }
        // Skeleton rows live inside the List/grid (see `listContent`/`gridContent`); the
        // empty/error message is an overlay fed the list's pull-to-refresh drag so it
        // rubber-bands with it. One animation cross-fades the whole state change.
        .overlay {
            ListStateOverlay(
                phase: listPhase,
                errorMessage: overlayErrorMessage,
                emptyIcon: IconKit.star,
                emptyMessage: L10n.Favorites.emptyList,
                noResultsMessage: L10n.EmptyState.noSearchMatches(store.searchQuery),
                pullOffset: pullOffset,
                onRetry: { store.send(store.isSearching ? .searchRetryTapped : .refreshButtonTapped) }
            )
        }
        .animation(DSMotion.contentReveal, value: listPhase)
        .featureToast(error: store.actionErrorMessage)
        .prefersToolbarItemsInVerticalBar()
        .toolbar {
            selectSortToolbar(
                isSelecting: store.isSelecting,
                isAllSelected: isAllSelected,
                isSelectAvailable: !store.favorites.isEmpty,
                isGridView: viewMode == .grid,
                onSelectModeToggled: { store.send(.selectModeToggled) },
                onSelectAllToggled: { store.send(isAllSelected ? .deselectAllTapped : .selectAllTapped) },
                onCancel: { store.send(.selectModeToggled) },
                onToggleViewMode: {
                    withAnimation {
                        viewModeRaw = (viewMode == .list ? FileListViewMode.grid : .list).rawValue
                    }
                },
                sortMenu: { EmptyView() }
            )
        }
        // Below the toolbar, so its Cancel can hide the circles before select mode ends.
        .selectModeChrome(isSelecting: store.isSelecting)
        .dsSheet(item: $store.scope(state: \.editSheet, action: \.editSheet)) { editStore in
            FavoriteEditSheet(store: editStore, onClose: { store.send(.editSheet(.dismiss)) })
        }
        // A tapped file result opens directly in this cover (no folder navigation).
        .modifier(PreviewHostCover(
            host: $store.scope(state: \.previewHost, action: \.previewHost),
            onViewShares: { store.send(.viewSharesFromPreviewTapped) }
        ))
        .hapticFeedback(.selection, trigger: viewModeRaw)
        .hapticFeedback(.selection, trigger: store.isSelecting)
        .toolbar {
            // The bar's actions only once something is picked, never greyed out over nothing. Showing
            // the saved list with no network, only taking kept folders off the device works, so with
            // nothing kept picked there is no bar at all.
            let isOffline = store.dataSource != .live
            let action = store.selectedOfflineAction
            if store.isSelecting, !store.selectedFavoriteIDs.isEmpty, !isOffline || action == .remove {
                #if os(iOS)
                    ToolbarItem(placement: .bottomBar) {
                        Spacer()
                    }
                #endif
                ToolbarItem(placement: .selectionBar) {
                    SelectionToolbarButton(
                        icon: action?.icon ?? IconKit.availableOffline,
                        tint: action == .remove ? .negative : nil,
                        accessibilityLabel: action?.title ?? L10n.Browse.actionAvailableOffline,
                        isDisabled: action == nil
                    ) {
                        store.send(.bulkOfflineTapped)
                    }
                }
                if !isOffline {
                    ToolbarItem(placement: .selectionBar) {
                        // Filled star, not trash: this only ever unfavorites the selection:
                        // the underlying folders/files aren't touched, so "delete" iconography
                        // would overstate what the action does.
                        SelectionToolbarButton(
                            icon: IconKit.starFill,
                            tint: .accent,
                            accessibilityLabel: L10n.Favorites.actionRemoveFromFavorites,
                            isDisabled: store.selectedFavoriteIDs.isEmpty
                        ) {
                            store.send(.bulkRemoveTapped)
                        }
                    }
                }
            }
        }
        .dsAlert(isPresented: bulkRemoveConfirmationBinding) {
            DSAlertSheet(
                icon: IconKit.unfavorite,
                title: bulkRemoveConfirmationTitle,
                message: L10n.Favorites.removeMessage,
                confirmTitle: L10n.Common.remove,
                dismissTitle: L10n.Common.cancel,
                role: .destructive,
                closeAccessibilityLabel: L10n.Common.close,
                onConfirm: { store.send(.bulkRemoveConfirmed) },
                onDismiss: { store.send(.bulkRemoveCancelled) }
            )
        }
        .hapticFeedback(.warning, trigger: store.bulkRemoveConfirmationIsPresented)
        .offlineRemovalAlert(
            store.offlineRemoval,
            onConfirm: { store.send(.offlineRemovalConfirmed) },
            onCancel: { store.send(.offlineRemovalCancelled) }
        )
        .navigationHistoryTitle(L10n.Favorites.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            store.send(.onAppear)
        }
        .onOfflinePhaseChange { phase in
            if phase == .completed {
                Task { @MainActor in store.send(.computeOfflineAvailability) }
            }
        }
    }

    private var listContent: some View {
        // Bound once: the separator checks below would otherwise re-filter the list per row.
        let favorites = store.displayedFavorites
        let firstID = favorites.first?.id
        let lastID = favorites.last?.id
        return DSGroupedList {
            if listPhase == .loading {
                SkeletonFileRows(entries: FavoritesSkeleton.entries)
            } else {
                ForEach(favorites) { favorite in
                    FavoriteListRow(
                        store: store,
                        favorite: favorite,
                        isFirst: favorite.id == firstID,
                        isLast: favorite.id == lastID
                    )
                }
                .onMove(perform: store.canReorder ? { store.send(.favoritesMoved($0, $1)) } : nil)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .backgroundGradient()
        .scrollPullOffset($pullOffset)
        .dismissKeyboardOnTap()
        // Only spring row diffs once the list is the content: during the skeleton→content
        // swap the outer `.animation(value: listPhase)` owns the cross-fade alone, so the two
        // don't run the same transition twice.
        .animation(listPhase == .content ? DSMotion.listDiff : nil, value: store.displayedFavorites)
    }

    private var gridContent: some View {
        ScrollView {
            LazyVGrid(columns: FileGridMetrics.columns(for: thumbnailSize), spacing: FileGridMetrics.spacing) {
                if listPhase == .loading {
                    SkeletonGridCells(entries: FavoritesSkeleton.entries)
                } else {
                    favoriteCells
                }
            }
            .padding(FileGridMetrics.spacing)
            .animation(listPhase == .content ? DSMotion.listDiff : nil, value: store.displayedFavorites)
        }
        .backgroundGradient()
        .scrollPullOffset($pullOffset)
        .dismissKeyboardOnTap()
    }

    private var favoriteCells: some View {
        ForEach(store.displayedFavorites) { favorite in
            FavoriteGridCell(store: store, favorite: favorite)
        }
    }
}

#Preview {
    FavoritesView(
        store: Store(
            initialState: FavoritesFeature.State(
                serverURL: URL(string: "https://nextexplorer.example.com") ?? URL(fileURLWithPath: "/")
            )
        ) {
            FavoritesFeature()
        } withDependencies: {
            $0.filesClient = .previewValue
        }
    )
}

#Preview("Empty") {
    FavoritesView(
        store: Store(
            initialState: FavoritesFeature.State(
                serverURL: URL(string: "https://nextexplorer.example.com") ?? URL(fileURLWithPath: "/")
            )
        ) {
            FavoritesFeature()
        } withDependencies: {
            $0.filesClient.favorites = { _ in [] }
        }
    )
}
