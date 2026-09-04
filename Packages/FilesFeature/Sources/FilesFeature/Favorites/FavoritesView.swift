import AppStorageKeys
import ComposableArchitecture
import CoreModels
import DesignSystem
import Localization
import SwiftUI

private enum FavoritesViewMode: String {
    case list, grid
}

private enum Constants {
    static let gridSpacing: CGFloat = .space16
    /// Inset between a grid tile's content and its `backgroundSecondary` card edge, matching
    /// `BrowseContentView`.
    static let gridCellPadding: CGFloat = .space12
    static let breadcrumbContentSpacing: CGFloat = .space8
    static let breadcrumbVisibilityAnimationDuration: Double = 0.25
}

struct FavoritesView: View {
    @Bindable var store: StoreOf<FavoritesFeature>
    @AppStorage(AppStorageKeys.favoritesViewMode) private var viewModeRaw = FavoritesViewMode.list.rawValue
    @AppStorage(AppStorageKeys.removeArchiveAfterDownload) private var removeArchiveAfterDownload = false
    /// Flipped once a pull-to-refresh completes, purely as a `.hapticFeedback` trigger — the
    /// value itself is meaningless, only the fact that it just changed matters.
    @State private var didFinishRefreshing = false
    /// How far the list is pulled below rest, fed to the empty/error overlay so it follows the
    /// pull-to-refresh rubber-band instead of staying pinned.
    @State private var pullOffset: CGFloat = 0

    private var viewMode: FavoritesViewMode {
        FavoritesViewMode(rawValue: viewModeRaw) ?? .list
    }

    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 100), spacing: Constants.gridSpacing)]
    }

    private var isAllSelected: Bool {
        !store.displayedFavorites.isEmpty && store.selectedFavoriteIDs.count == store.displayedFavorites.count
    }

    /// The one screen state, derived from the store — skeleton until the first response lands
    /// (`store.phase`), then error / empty / no-results / the list. `phase.errorMessage` is
    /// non nil only on a first load failure with nothing to show, so it needs no empty guard.
    private var listPhase: ListPhase {
        if store.errorMessage != nil { return .error }
        if !store.phase.hasLoaded && store.favorites.isEmpty { return .loading }
        if store.favorites.isEmpty { return .empty }
        // While searching, the screen shows recursive file results across the favorited folders,
        // so its phase follows `searchPhase`/results, not the favorites list.
        if store.isSearching {
            if store.searchPhase.errorMessage != nil && store.fileSearchResults == nil { return .error }
            if !store.searchPhase.hasLoaded && store.fileSearchResults == nil { return .loading }
            return store.displayedSearchResults.isEmpty ? .noResults : .content
        }
        return .content
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

    /// The topmost pushed screen's path — mirrors `BrowseTabView`'s persistent breadcrumb
    /// bar, since browsing into a favorited folder now stays inside this tab (pushing
    /// `BrowseFeature` screens) instead of jumping to Browse.
    private var currentDirectoryPath: String {
        store.path.last?.directoryPath ?? ""
    }

    /// The favorited folder itself — the *first* pushed screen, regardless of how deep
    /// `path` currently goes — anchors the breadcrumb instead of the true server root:
    /// browsing from Favorites is scoped to that one subtree, so server "Home" isn't
    /// reachable from here at all.
    private var rootDirectoryPath: String {
        store.path.first?.directoryPath ?? ""
    }

    private var rootTitle: String {
        store.path.first?.title ?? ""
    }

    private var isTopScreenSelecting: Bool {
        store.path.last?.isSelecting ?? false
    }

    var body: some View {
        NavigationStack(path: $store.scope(state: \.path, action: \.path)) {
            rootContent
        } destination: { store in
            BrowseContentView(store: store)
                .navigationTitle("")
        }
        .safeAreaInset(edge: .bottom, spacing: Constants.breadcrumbContentSpacing) {
            if !currentDirectoryPath.isEmpty && !isTopScreenSelecting {
                BrowseBreadcrumbBar(
                    directoryPath: currentDirectoryPath,
                    rootTitle: rootTitle,
                    rootPath: rootDirectoryPath,
                    rootIcon: IconKit.folderFill,
                    containerCrumb: (L10n.Favorites.navigationTitle, "", IconKit.starFill)
                ) { path, title in
                    store.send(.navigateToDirectory(path: path, title: title))
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: Constants.breadcrumbVisibilityAnimationDuration), value: isTopScreenSelecting)
        .tint(Color.accent)
    }

    private var rootContent: some View {
        Group {
                if store.isSearching {
                    searchResultsContent
                } else if viewMode == .list {
                    listContent
                } else {
                    gridContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .top, spacing: 0) {
                PinnedTitleSearchHeader(
                    title: store.isSelecting ? L10n.Common.selectedCount(store.selectedFavoriteIDs.count) : L10n.Favorites.navigationTitle,
                    searchText: $store.searchQuery.sending(\.searchQueryChanged)
                )
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if case let .cached(fetchedAt) = store.dataSource {
                    DSInfoCard(L10n.Browse.offlineBannerDetail(OfflineRelativeTime.string(from: fetchedAt)))
                        .padding(.horizontal, .space16)
                        .padding(.vertical, .space8)
                        .background(Color.backgroundPrimary)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: store.dataSource)
            .refreshable {
                await store.send(.refreshButtonTapped).finish()
                didFinishRefreshing.toggle()
            }
            .hapticFeedback(.success, trigger: didFinishRefreshing) { _, _ in store.errorMessage == nil }
            .hapticFeedback(.error, trigger: store.errorMessage) { _, newValue in newValue != nil }
            .syncCompletedToast(trigger: didFinishRefreshing, isErrorFree: store.errorMessage == nil)
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
            .toolbar(store.isSelecting ? .hidden : .automatic, for: .tabBar)
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
                            viewModeRaw = (viewMode == .list ? FavoritesViewMode.grid : .list).rawValue
                        }
                    },
                    sortMenu: { EmptyView() }
                )
            }
            .sheet(item: $store.scope(state: \.editSheet, action: \.editSheet)) { editStore in
                FavoriteEditSheet(store: editStore, onClose: { store.send(.editSheet(.dismiss)) })
            }
            // A tapped file result opens directly in this cover (no folder navigation); the host
            // `BrowseFeature` drives the same preview router Browse uses.
            .fullScreenCover(item: $store.scope(state: \.previewHost, action: \.previewHost)) { hostStore in
                if let previewItem = hostStore.previewItem {
                    BrowsePreviewRouter(
                        store: hostStore,
                        item: previewItem,
                        removeArchiveAfterDownload: removeArchiveAfterDownload,
                        onShareTarget: { _ in }
                    )
                }
            }
            .hapticFeedback(.selection, trigger: viewModeRaw)
            .hapticFeedback(.selection, trigger: store.isSelecting)
            .toolbar {
                if store.isSelecting {
                    ToolbarItem(placement: .bottomBar) {
                        Spacer()
                    }
                    ToolbarItem(placement: .bottomBar) {
                        // Filled star, not trash: this only ever unfavorites the selection —
                        // the underlying folders/files aren't touched, so "delete" iconography
                        // would overstate what the action does.
                        Button {
                            store.send(.bulkRemoveTapped)
                        } label: {
                            IconKit.starFill
                        }
                        .buttonStyle(DSHapticButtonStyle())
                        .foregroundStyle(Color.accent)
                        .accessibilityLabel(L10n.Favorites.actionRemoveFromFavorites)
                        .disabled(store.selectedFavoriteIDs.isEmpty)
                    }
                }
            }
            .sheet(isPresented: bulkRemoveConfirmationBinding) {
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
            // Title lives in the pinned header (see `PinnedTitleSearchHeader`).
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                store.send(.onAppear)
            }
    }

    private func handleTap(_ favorite: Favorite) {
        if store.isSelecting {
            store.send(.itemSelectionToggled(favorite.id))
        } else {
            store.send(.rowTapped(favorite))
        }
    }


    private func favoriteRowIcon(_ favorite: Favorite) -> some View {
        FileRowView(
            name: favorite.displayName,
            isDirectory: true,
            customIcon: FavoriteIcon.symbol(for: favorite.icon),
            customIconTint: FavoriteColor.resolve(favorite.color),
            customIconFilled: FavoriteIcon.isFilled(favorite.icon)
        )
    }

    /// Redacted `FileRowView` / `GridCellView` stand-ins that sit in the *same* `List` / grid
    /// as the real rows — never a separate scroll container (that fights the nav bar's large
    /// title). Shine suppressed under Reduce Motion.
    private static let skeletonNames = [6, 12, 4, 9, 15, 7, 11, 5, 13, 8].map { String(repeating: "M", count: $0) }

    @ViewBuilder
    private var skeletonRows: some View {
        ForEach(Self.skeletonNames, id: \.self) { name in
            FileRowView(name: name, isDirectory: true)
                .redacted(reason: .placeholder)
                .shimmering()
                .listRowBackground(Color.backgroundSecondary)
        }
    }

    @ViewBuilder
    private var skeletonCells: some View {
        ForEach(Self.skeletonNames, id: \.self) { name in
            GridCellView(name: name, isDirectory: true)
                .dsCard(padding: Constants.gridCellPadding)
                .redacted(reason: .placeholder)
                .shimmering()
        }
    }

    private var listContent: some View {
        // Bound once — the separator checks below would otherwise re-filter the list per row.
        let favorites = store.displayedFavorites
        let firstID = favorites.first?.id
        let lastID = favorites.last?.id
        return List {
            if listPhase == .loading {
                skeletonRows
            } else {
            ForEach(favorites) { favorite in
                Button {
                    handleTap(favorite)
                } label: {
                    HStack(spacing: .space12) {
                        if store.isSelecting {
                            DSSelectionIndicator(isSelected: store.selectedFavoriteIDs.contains(favorite.id))
                        }
                        favoriteRowIcon(favorite)
                    }
                }
                .buttonStyle(DSHapticButtonStyle())
                .accessibilityAddTraits(store.isSelecting && store.selectedFavoriteIDs.contains(favorite.id) ? [.isSelected] : [])
                .listRowBackground(Color.backgroundSecondary)
                .contextMenu {
                    if !store.isSelecting {
                        FavoriteRowContextMenu(store: store, favorite: favorite)
                    }
                }
                .swipeActions(edge: .leading) {
                    if !store.isSelecting {
                        Button {
                            store.send(.editTapped(favorite))
                        } label: {
                            IconKit.rename
                        }
                        .tint(.accent)
                        .accessibilityLabel(L10n.Favorites.actionEdit)
                    }
                }
                .swipeActions(edge: .trailing) {
                    if !store.isSelecting {
                        // Unfavoriting doesn't touch the folder itself, so the swipe reads in
                        // accent rather than destructive red.
                        Button {
                            store.send(.removeTapped(favorite))
                        } label: {
                            IconKit.unfavorite
                        }
                        .tint(.accent)
                        .accessibilityLabel(L10n.Favorites.actionRemoveFromFavorites)
                    }
                }
                .listRowSeparator(favorite.id == firstID ? .hidden : .visible, edges: .top)
                .listRowSeparator(favorite.id == lastID ? .hidden : .visible, edges: .bottom)
            }
            .onMove(perform: store.canReorder ? { store.send(.favoritesMoved($0, $1)) } : nil)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .backgroundGradient()
        .scrollPullOffset($pullOffset)
        .dismissKeyboardOnTap()
        // Only spring row diffs once the list is the content — during the skeleton→content
        // swap the outer `.animation(value: listPhase)` owns the cross-fade alone, so the two
        // don't run the same transition twice.
        .animation(listPhase == .content ? DSMotion.listDiff : nil, value: store.displayedFavorites)
    }

    /// Recursive file search results across the favorited folders, shown in place of the favorites
    /// list while a query is active. Same inset-grouped styling as `listContent`; tapping a hit
    /// pushes its containing folder and opens the file.
    private var searchResultsContent: some View {
        let results = store.displayedSearchResults
        let firstID = results.first?.id
        let lastID = results.last?.id
        return List {
            if listPhase == .loading {
                skeletonRows
            } else {
                ForEach(results) { result in
                    Button {
                        store.send(.searchResultTapped(result))
                    } label: {
                        FileRowView(
                            name: result.name,
                            isDirectory: result.isDirectory,
                            subtitle: searchResultSnippet(result),
                            lineLabel: searchResultLineLabel(result),
                            kind: searchResultKind(result)
                        )
                    }
                    .buttonStyle(DSHapticButtonStyle())
                    .listRowBackground(Color.backgroundSecondary)
                    .listRowSeparator(result.id == firstID ? .hidden : .visible, edges: .top)
                    .listRowSeparator(result.id == lastID ? .hidden : .visible, edges: .bottom)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .backgroundGradient()
        .scrollPullOffset($pullOffset)
        .dismissKeyboardOnTap()
        .animation(listPhase == .content ? DSMotion.listDiff : nil, value: store.fileSearchResults)
    }

    private func searchResultKind(_ result: SearchResultItem) -> String {
        result.isDirectory ? result.kind : (result.name as NSString).pathExtension.lowercased()
    }

    private var gridContent: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: Constants.gridSpacing) {
                if listPhase == .loading {
                    skeletonCells
                } else {
                    favoriteCells
                }
            }
            .padding(Constants.gridSpacing)
            .animation(listPhase == .content ? DSMotion.listDiff : nil, value: store.displayedFavorites)
        }
        .backgroundGradient()
        .scrollPullOffset($pullOffset)
        .dismissKeyboardOnTap()
    }

    @ViewBuilder
    private var favoriteCells: some View {
        ForEach(store.displayedFavorites) { favorite in
                    Button {
                        handleTap(favorite)
                    } label: {
                        GridCellView(
                            name: favorite.displayName,
                            isDirectory: true,
                            customIcon: FavoriteIcon.symbol(for: favorite.icon),
                            customIconTint: FavoriteColor.resolve(favorite.color),
                            customIconFilled: FavoriteIcon.isFilled(favorite.icon)
                        )
                            .dsCard(padding: Constants.gridCellPadding)
                            .overlay(alignment: .topLeading) {
                                if store.isSelecting {
                                    DSSelectionIndicator(isSelected: store.selectedFavoriteIDs.contains(favorite.id))
                                }
                            }
                    }
                    .buttonStyle(DSHapticButtonStyle())
                    .hapticFeedback(.selection, trigger: store.selectedFavoriteIDs.contains(favorite.id))
                    .contextMenu {
                        if !store.isSelecting {
                            FavoriteRowContextMenu(store: store, favorite: favorite)
                        }
                    }
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
