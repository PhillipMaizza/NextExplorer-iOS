import ComposableArchitecture
import CoreModels
import DesignSystem
import SwiftUI

private enum BrowseViewMode: String {
    case list, grid
}

private enum Constants {
    static let emptyStateSpacing: CGFloat = .space8
    static let emptyStateIconSize: CGFloat = .superIcon
    static let gridItemMinWidth: CGFloat = 100
    static let gridColumns = [GridItem(.adaptive(minimum: gridItemMinWidth), spacing: .space16)]
    static let gridSpacing: CGFloat = .space16
}

/// The list body shown at every depth of Browse: root and every pushed subfolder
/// render this same view, scoped to their own `BrowseFeature` store. The list/grid
/// choice is a per-device display preference, not per-folder state, so it's stored
/// directly here rather than threaded through `BrowseFeature.State`.
struct BrowseContentView: View {
    @Bindable var store: StoreOf<BrowseFeature>
    @AppStorage("browseViewMode") private var viewModeRaw = BrowseViewMode.list.rawValue
    @State private var isSortSheetPresented = false

    private var viewMode: BrowseViewMode {
        BrowseViewMode(rawValue: viewModeRaw) ?? .list
    }

    var body: some View {
        Group {
            if viewMode == .list {
                listContent
            } else {
                gridContent
            }
        }
        .tint(Color.accent)
        #if os(iOS)
        .searchable(
            text: $store.searchQuery.sending(\.searchQueryChanged),
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search"
        )
        #else
        .searchable(
            text: $store.searchQuery.sending(\.searchQueryChanged),
            prompt: "Search"
        )
        #endif
        .searchScopes($store.searchScope.sending(\.searchScopeChanged)) {
            ForEach(BrowseFeature.SearchScope.allCases, id: \.self) { scope in
                Text(scope.title).tag(scope)
            }
        }
        .refreshable {
            store.send(.refreshButtonTapped)
        }
        .overlay {
            overlayStateContent
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !store.directoryPath.isEmpty {
                BrowseBreadcrumbBar(directoryPath: store.directoryPath) { path, title in
                    store.send(.breadcrumbTapped(path: path, title: title))
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isSortSheetPresented = true
                } label: {
                    IconKit.arrowUpArrowDown
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    viewModeRaw = (viewMode == .list ? BrowseViewMode.grid : .list).rawValue
                } label: {
                    viewMode == .list ? IconKit.squareGrid : IconKit.listBullet
                }
            }
        }
        .sheet(isPresented: $isSortSheetPresented) {
            BrowseSortSheet(
                sortOption: store.sortOption,
                sortDirection: store.sortDirection,
                onSelectOption: { store.send(.sortOptionChanged($0)) },
                onSelectDirection: { store.send(.sortDirectionChanged($0)) },
                onDismiss: { isSortSheetPresented = false }
            )
        }
        .task {
            store.send(.onAppear)
        }
    }

    @ViewBuilder
    private var overlayStateContent: some View {
        if store.isLoading && store.items.isEmpty {
            ProgressView()
        } else if let errorMessage = store.errorMessage {
            EmptyStateView(icon: IconKit.exclamationmarkTriangle, message: errorMessage)
        } else if !store.isSearching && store.displayedItems.isEmpty {
            EmptyStateView(icon: IconKit.folder, message: "This folder is empty.")
        } else if store.isSearching && store.searchScope == .everywhere && store.isSearchingEverywhere {
            ProgressView()
        } else if store.isSearching, let results = store.displayedSearchResults, results.isEmpty {
            noResultsState
        }
    }

    private var listContent: some View {
        List {
            if store.isSearching {
                searchResultRows
            } else {
                folderItemRows
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.backgroundPrimary)
    }

    private var gridContent: some View {
        ScrollView {
            LazyVGrid(columns: Constants.gridColumns, spacing: Constants.gridSpacing) {
                if store.isSearching {
                    ForEach(store.displayedSearchResults ?? []) { result in
                        Button {
                            store.send(.searchResultTapped(result))
                        } label: {
                            GridCellView(name: result.name, isDirectory: result.isDirectory, isFavorite: store.favoritePaths.contains(result.id))
                        }
                        .buttonStyle(.plain)
                        .disabled(!result.isDirectory)
                    }
                } else {
                    ForEach(store.displayedItems) { item in
                        Button {
                            store.send(.rowTapped(item))
                        } label: {
                            GridCellView(name: item.name, isDirectory: item.isDirectory, isFavorite: store.favoritePaths.contains(item.id))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(Constants.gridSpacing)
        }
        .background(Color.backgroundPrimary)
    }

    @ViewBuilder
    private var folderItemRows: some View {
        ForEach(store.displayedItems) { item in
            Button {
                store.send(.rowTapped(item))
            } label: {
                FileRowView(item: item, isFavorite: store.favoritePaths.contains(item.id))
            }
            .buttonStyle(.plain)
            .listRowBackground(Color.clear)
        }
    }

    @ViewBuilder
    private var searchResultRows: some View {
        ForEach(store.displayedSearchResults ?? []) { result in
            Button {
                store.send(.searchResultTapped(result))
            } label: {
                FileRowView(name: result.name, isDirectory: result.isDirectory, subtitle: result.matchLine, isFavorite: store.favoritePaths.contains(result.id))
            }
            .buttonStyle(.plain)
            .disabled(!result.isDirectory)
            .listRowBackground(Color.clear)
        }
    }

    @ViewBuilder
    private var noResultsState: some View {
        VStack(spacing: Constants.emptyStateSpacing) {
            IconKit.magnifyingGlass
                .resizable()
                .scaledToFit()
                .foregroundStyle(Color.secondaryDS)
                .frame(width: Constants.emptyStateIconSize, height: Constants.emptyStateIconSize)
            Text("No matches for \u{201C}\(store.searchQuery)\u{201D}.")
                .type(.body1(.semibold), style: .secondary)
            if store.searchScope == .thisFolder {
                DSButton("Search everywhere",
                         icon: IconKit.magnifyingGlass,
                         style: .secondary,
                         size: .small,
                         isLoading: false, action: {
                        store.send(.searchScopeChanged(.everywhere))
                })
                .padding(.top, Constants.emptyStateSpacing)
            }
        }
        .padding(.space16)
        .multilineTextAlignment(.center)
    }
}

#Preview("BrowseContentView") {
    NavigationStack {
        BrowseContentView(
            store: Store(
                initialState: BrowseFeature.State(
                    serverURL: URL(string: "https://nextexplorer.example.com") ?? URL(fileURLWithPath: "/"),
                    directoryPath: "",
                    title: "Browse"
                )
            ) {
                BrowseFeature()
            } withDependencies: {
                $0.filesClient = .previewValue
            }
        )
        .navigationTitle("Browse")
    }
}

