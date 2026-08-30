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
    static let listDiffSpringResponse: Double = 0.35
    static let listDiffSpringDamping: Double = 0.8
    static let overlayCrossfadeDuration: Double = 0.2
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
    /// Flipped once a pull-to-refresh completes, purely as a `.hapticFeedback` trigger — the
    /// value itself is meaningless, only the fact that it just changed matters.
    @State private var didFinishRefreshing = false

    private var viewMode: FavoritesViewMode {
        FavoritesViewMode(rawValue: viewModeRaw) ?? .list
    }

    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 100), spacing: Constants.gridSpacing)]
    }

    private var isAllSelected: Bool {
        !store.displayedFavorites.isEmpty && store.selectedFavoriteIDs.count == store.displayedFavorites.count
    }

    private var overlayPhase: ListStateOverlay.Phase {
        if store.isLoading && store.favorites.isEmpty {
            .loading
        } else if store.errorMessage != nil {
            .error
        } else if store.favorites.isEmpty {
            .empty
        } else if !store.searchQuery.isEmpty && store.displayedFavorites.isEmpty {
            .noResults
        } else {
            .none
        }
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
                .navigationTitle(store.isSelecting ? L10n.Common.selectedCount(store.selectedItemIDs.count) : store.title)
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
                if viewMode == .list {
                    listContent
                } else {
                    gridContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .searchable(
                text: $store.searchQuery.sending(\.searchQueryChanged),
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: L10n.Common.search
            )
            .refreshable {
                await store.send(.refreshButtonTapped).finish()
                didFinishRefreshing.toggle()
            }
            .hapticFeedback(.success, trigger: didFinishRefreshing) { _, _ in store.errorMessage == nil }
            .hapticFeedback(.error, trigger: store.errorMessage) { _, newValue in newValue != nil }
            .overlay {
                ListStateOverlay(
                    phase: overlayPhase,
                    errorMessage: store.errorMessage,
                    emptyIcon: IconKit.star,
                    emptyMessage: L10n.Favorites.emptyList,
                    noResultsMessage: L10n.EmptyState.noSearchMatches(store.searchQuery),
                    onRetry: { store.send(.refreshButtonTapped) }
                )
            }
            .animation(.easeInOut(duration: Constants.overlayCrossfadeDuration), value: overlayPhase)
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
            .navigationTitle(store.isSelecting ? L10n.Common.selectedCount(store.selectedFavoriteIDs.count) : L10n.Favorites.navigationTitle)
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

    @ViewBuilder
    private func rowContextMenu(for favorite: Favorite) -> some View {
        Button {
            store.send(.editTapped(favorite))
        } label: {
            Label { Text(L10n.Favorites.actionEdit) } icon: { IconKit.rename }
        }
        Button(role: .destructive) {
            store.send(.removeTapped(favorite))
        } label: {
            Label { Text(L10n.Favorites.actionRemoveFromFavorites) } icon: { IconKit.unfavorite }
        }
        .tint(.negative)
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

    private var listContent: some View {
        // Bound once — the separator checks below would otherwise re-filter the list per row.
        let favorites = store.displayedFavorites
        let firstID = favorites.first?.id
        let lastID = favorites.last?.id
        return List {
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
                .listRowBackground(Color.backgroundSecondary)
                .contextMenu {
                    if !store.isSelecting {
                        rowContextMenu(for: favorite)
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
                    }
                }
                .listRowSeparator(favorite.id == firstID ? .hidden : .visible, edges: .top)
                .listRowSeparator(favorite.id == lastID ? .hidden : .visible, edges: .bottom)
            }
            .onMove(perform: store.canReorder ? { store.send(.favoritesMoved($0, $1)) } : nil)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .backgroundGradient()
        .animation(
            .spring(response: Constants.listDiffSpringResponse, dampingFraction: Constants.listDiffSpringDamping),
            value: store.displayedFavorites
        )
    }

    private var gridContent: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: Constants.gridSpacing) {
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
                            rowContextMenu(for: favorite)
                        }
                    }
                }
            }
            .padding(Constants.gridSpacing)
            .animation(
                .spring(response: Constants.listDiffSpringResponse, dampingFraction: Constants.listDiffSpringDamping),
                value: store.displayedFavorites
            )
        }
        .backgroundGradient()
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
