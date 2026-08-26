import ComposableArchitecture
import CoreModels
import DesignSystem
import SwiftUI

private enum Constants {
    static let listDiffSpringResponse: Double = 0.35
    static let listDiffSpringDamping: Double = 0.8
    static let overlayCrossfadeDuration: Double = 0.2
}

struct FavoritesView: View {
    @Bindable var store: StoreOf<FavoritesFeature>
    @State private var searchQuery = ""
    /// Flipped once a pull-to-refresh completes, purely as a `.hapticFeedback` trigger — the
    /// value itself is meaningless, only the fact that it just changed matters.
    @State private var didFinishRefreshing = false

    /// Purely a client-side filter/sort over the already-loaded list, no reducer round trip
    /// needed. Always alphabetical: the server returns favorites in insertion order
    /// (`position ASC, created_at ASC`), which would otherwise put a newly-added favorite
    /// at the end of the list instead of where it belongs alphabetically.
    private var displayedFavorites: [Favorite] {
        let matches = searchQuery.isEmpty
            ? Array(store.favorites)
            : store.favorites.filter { FuzzyMatch.matches(query: searchQuery, in: $0.displayName) }
        return matches.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    /// Which branch of the overlay is currently showing — lets the overlay cross-fade
    /// between states instead of hard-cutting between them.
    private enum OverlayState: Equatable {
        case none, loading, error, empty, noResults
    }

    private var overlayState: OverlayState {
        if store.isLoading && store.favorites.isEmpty {
            .loading
        } else if store.errorMessage != nil {
            .error
        } else if store.favorites.isEmpty {
            .empty
        } else if !searchQuery.isEmpty && displayedFavorites.isEmpty {
            .noResults
        } else {
            .none
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(displayedFavorites) { favorite in
                    Button {
                        store.send(.rowTapped(favorite))
                    } label: {
                        FileRowView(name: favorite.displayName, isDirectory: true)
                    }
                    .buttonStyle(DSHapticButtonStyle())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(favorite.id == displayedFavorites.first?.id ? .hidden : .visible, edges: .top)
                    .listRowSeparator(favorite.id == displayedFavorites.last?.id ? .hidden : .visible, edges: .bottom)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.backgroundPrimary)
            .animation(
                .spring(response: Constants.listDiffSpringResponse, dampingFraction: Constants.listDiffSpringDamping),
                value: displayedFavorites
            )
            .searchable(
                text: $searchQuery,
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
                switch overlayState {
                case .loading:
                    ProgressView()
                        .transition(.opacity)
                case .error:
                    if let errorMessage = store.errorMessage {
                        EmptyStateView(icon: IconKit.exclamationmarkTriangle, message: errorMessage)
                            .transition(.opacity)
                    }
                case .empty:
                    EmptyStateView(icon: IconKit.star, message: "Star folders in Browse to see them here.")
                        .transition(.opacity)
                case .noResults:
                    EmptyStateView(icon: IconKit.magnifyingGlass, message: "No matches for \u{201C}\(searchQuery)\u{201D}.")
                        .transition(.opacity)
                case .none:
                    EmptyView()
                }
            }
            .animation(.easeInOut(duration: Constants.overlayCrossfadeDuration), value: overlayState)
            .navigationTitle("Favorites")
            .task {
                store.send(.onAppear)
            }
        }
        .tint(Color.accent)
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
