import ComposableArchitecture
import CoreModels
import DesignSystem
import SwiftUI

private enum FavoritesViewMode: String {
    case list, grid
}

private enum Constants {
    static let listDiffSpringResponse: Double = 0.35
    static let listDiffSpringDamping: Double = 0.8
    static let overlayCrossfadeDuration: Double = 0.2
    static let gridSpacing: CGFloat = .space16
    static let breadcrumbContentSpacing: CGFloat = .space8
    static let breadcrumbVisibilityAnimationDuration: Double = 0.25
}

struct FavoritesView: View {
    @Bindable var store: StoreOf<FavoritesFeature>
    @AppStorage("favoritesViewMode") private var viewModeRaw = FavoritesViewMode.list.rawValue
    @State private var isSortSheetPresented = false
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

    /// Which branch of the overlay is currently showing — lets the overlay cross-fade
    /// between states instead of hard-cutting between them.
    private enum OverlayState: Hashable {
        case none, loading, error, empty, noResults
    }

    private var overlayState: OverlayState {
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
        Binding(
            get: { store.bulkRemoveConfirmationIsPresented },
            set: { if !$0 { store.send(.bulkRemoveCancelled) } }
        )
    }

    private var bulkRemoveConfirmationTitle: String {
        "Remove \(store.selectedFavoriteIDs.count) Favorite\(store.selectedFavoriteIDs.count == 1 ? "" : "s")?"
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
                .navigationTitle(store.isSelecting ? "\(store.selectedItemIDs.count) Selected" : store.title)
        }
        .safeAreaInset(edge: .bottom, spacing: Constants.breadcrumbContentSpacing) {
            if !currentDirectoryPath.isEmpty && !isTopScreenSelecting {
                BrowseBreadcrumbBar(
                    directoryPath: currentDirectoryPath,
                    rootTitle: rootTitle,
                    rootPath: rootDirectoryPath,
                    rootIcon: IconKit.folderFill,
                    containerCrumb: ("Favorites", "", IconKit.starFill)
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
                prompt: "Search"
            )
            .refreshable {
                await store.send(.refreshButtonTapped).finish()
                didFinishRefreshing.toggle()
            }
            .hapticFeedback(.success, trigger: didFinishRefreshing) { _, _ in store.errorMessage == nil }
            .hapticFeedback(.error, trigger: store.errorMessage) { _, newValue in newValue != nil }
            .overlay {
                Group {
                    switch overlayState {
                    case .loading:
                        ProgressView()
                            .transition(.opacity)
                    case .error:
                        if let errorMessage = store.errorMessage {
                            EmptyStateView(icon: IconKit.warning, message: errorMessage)
                                .transition(.opacity)
                        }
                    case .empty:
                        EmptyStateView(icon: IconKit.star, message: "Star folders in Browse to see them here.")
                            .transition(.opacity)
                    case .noResults:
                        EmptyStateView(icon: IconKit.search, message: "No matches for \u{201C}\(store.searchQuery)\u{201D}.")
                            .transition(.opacity)
                    case .none:
                        EmptyView()
                    }
                }
                .id(overlayState)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .animation(.easeInOut(duration: Constants.overlayCrossfadeDuration), value: overlayState)
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
                    }
                ) {
                    Button {
                        isSortSheetPresented = true
                    } label: {
                        Label { Text("Sort") } icon: { IconKit.sort }
                    }
                }
            }
            .sheet(isPresented: $isSortSheetPresented) {
                SortSheet(
                    options: FavoritesFeature.SortOption.allCases,
                    directions: BrowseFeature.SortDirection.allCases,
                    sortOption: store.sortOption,
                    sortDirection: store.sortDirection,
                    optionIcon: { $0.icon },
                    optionTitle: { $0.title },
                    directionIcon: { $0.icon },
                    directionTitle: { $0.title },
                    onSelectOption: { store.send(.sortOptionChanged($0)) },
                    onSelectDirection: { store.send(.sortDirectionChanged($0)) },
                    onDismiss: { isSortSheetPresented = false }
                )
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
            .alert(bulkRemoveConfirmationTitle, isPresented: bulkRemoveConfirmationBinding) {
                Button("Remove", role: .destructive) { store.send(.bulkRemoveConfirmed) }
                Button("Cancel", role: .cancel) { store.send(.bulkRemoveCancelled) }
            } message: {
                Text("This only removes them from Favorites.")
            }
            .hapticFeedback(.warning, trigger: store.bulkRemoveConfirmationIsPresented)
            .navigationTitle(store.isSelecting ? "\(store.selectedFavoriteIDs.count) Selected" : "Favorites")
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
        Button(role: .destructive) {
            store.send(.removeTapped(favorite))
        } label: {
            Label { Text("Remove from Favorites") } icon: { IconKit.unfavorite }
        }
        .tint(.negative)
    }

    private func selectionIndicator(isSelected: Bool) -> some View {
        (isSelected ? IconKit.checkmarkCircleFill : IconKit.radioUnselected)
            .resizable()
            .scaledToFit()
            .foregroundStyle(isSelected ? Color.accent : Color.secondaryDS)
            .frame(width: .iconMedium, height: .iconMedium)
            .symbolEffect(.bounce, value: isSelected)
            .transition(.scale.combined(with: .opacity))
    }

    private var listContent: some View {
        List {
            ForEach(store.displayedFavorites) { favorite in
                Button {
                    handleTap(favorite)
                } label: {
                    HStack(spacing: .space12) {
                        if store.isSelecting {
                            selectionIndicator(isSelected: store.selectedFavoriteIDs.contains(favorite.id))
                        }
                        FileRowView(name: favorite.displayName, isDirectory: true)
                    }
                }
                .buttonStyle(DSHapticButtonStyle())
                .listRowBackground(Color.clear)
                .contextMenu {
                    if !store.isSelecting {
                        rowContextMenu(for: favorite)
                    }
                }
                .swipeActions(edge: .trailing) {
                    if !store.isSelecting {
                        Button(role: .destructive) {
                            store.send(.removeTapped(favorite))
                        } label: {
                            IconKit.unfavorite
                        }
                        .tint(.negative)
                    }
                }
                .listRowSeparator(favorite.id == store.displayedFavorites.first?.id ? .hidden : .visible, edges: .top)
                .listRowSeparator(favorite.id == store.displayedFavorites.last?.id ? .hidden : .visible, edges: .bottom)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.backgroundPrimary)
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
                        GridCellView(name: favorite.displayName, isDirectory: true)
                            .overlay(alignment: .topLeading) {
                                if store.isSelecting {
                                    selectionIndicator(isSelected: store.selectedFavoriteIDs.contains(favorite.id))
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
        .background(Color.backgroundPrimary)
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
