import ComposableArchitecture
import CoreModels
import DesignSystem
import SwiftUI

struct FavoritesView: View {
    @Bindable var store: StoreOf<FavoritesFeature>
    @State private var searchQuery = ""

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

    var body: some View {
        NavigationStack {
            List {
                ForEach(displayedFavorites) { favorite in
                    Button {
                        store.send(.rowTapped(favorite))
                    } label: {
                        FileRowView(name: favorite.displayName, isDirectory: true)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.backgroundPrimary)
            #if os(iOS)
            .searchable(
                text: $searchQuery,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search"
            )
            #else
            .searchable(text: $searchQuery, prompt: "Search")
            #endif
            .refreshable {
                store.send(.refreshButtonTapped)
            }
            .overlay {
                if store.isLoading && store.favorites.isEmpty {
                    ProgressView()
                } else if let errorMessage = store.errorMessage {
                    EmptyStateView(icon: IconKit.exclamationmarkTriangle, message: errorMessage)
                } else if store.favorites.isEmpty {
                    EmptyStateView(icon: IconKit.star, message: "Star folders in Browse to see them here.")
                } else if !searchQuery.isEmpty && displayedFavorites.isEmpty {
                    EmptyStateView(icon: IconKit.magnifyingGlass, message: "No matches for \u{201C}\(searchQuery)\u{201D}.")
                }
            }
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
