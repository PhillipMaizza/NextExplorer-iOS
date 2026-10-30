import ComposableArchitecture
import CoreModels
import FilesClient
import Foundation

extension BrowseFeature {
    /// Both scopes run a recursive, content aware `/api/search` (only the base path differs),
    /// debounced so a burst of keystrokes fires one request. A client side pre-fill from the
    /// already-loaded folder paints instantly while that request is in flight.
    func search(_ state: inout State) -> Effect<Action> {
        // Trim like the backend does before its own empty check, so an all-whitespace query is
        // treated as empty rather than pre-filling everything and 400ing on a blank `q`.
        let query = state.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            state.searchResults = nil
            state.isSearchingRemotely = false
            state.searchShortfall = nil
            state.selectedSearchCategories = []
            return .cancel(id: CancelID.search)
        }

        // Instant client side pre-fill from the already loaded folder, so results appear the
        // moment the user types while the recursive backend search runs. These are name matches
        // in the current folder only: a subset of what either scope's backend search returns, so
        // the authoritative response only ever adds to them (subfolders + content matches).
        // Deliberately does NOT prune `selectedSearchCategories`: the pre-fill sees only this
        // folder, so a selected category the backend subtree contains but this folder lacks would
        // be wrongly cleared. Pruning happens against the authoritative response instead.
        let preliminary = state.items
            .filter { SearchMatch.matches(query: query, in: $0.name) }
            .map { SearchResultItem(name: $0.name, path: $0.path, kind: $0.isDirectory ? "dir" : "file") }
        let results = preliminary + Self.favoriteMatches(state, query: query)
        state.searchResults = IdentifiedArray(Self.sortedAlphabetically(results), id: \.id, uniquingIDsWith: { first, _ in first })
        // The server only searches from three characters on; until then the instant matches stand.
        guard query.count >= FilesClient.minimumSearchTermLength else {
            state.isSearchingRemotely = false
            state.searchShortfall = nil
            return .cancel(id: CancelID.search)
        }
        state.isSearchingRemotely = true
        return fetchSearchResults(state, isDebounced: true)
    }

    /// The server search on its own, without the instant pre-fill: Show more widens the answer
    /// already on screen rather than starting over from the local matches.
    func fetchSearchResults(_ state: State, isDebounced: Bool) -> Effect<Action> {
        let query = state.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        // Both scopes hit the same recursive, content aware backend endpoint; only the base path
        // differs. "This Folder" scopes to the current directory (its whole subtree); "Everywhere"
        // searches from the root.
        let scopePath = state.searchScope == .everywhere ? "" : state.directoryPath
        let serverURL = state.serverURL
        let filesClient = filesClient
        let clock = clock
        let limit = state.searchLimit

        return .run { send in
            if isDebounced {
                try await clock.sleep(for: Constants.searchDebounce)
            }
            try await send(.searchResultsResponse(apiResult {
                try await filesClient.search(serverURL, scopePath, query, limit)
            }))
        }
        .cancellable(id: CancelID.search, cancelInFlight: true)
    }

    /// Favorites whose name matches, inside the search scope, so a favorite is there to open
    /// the moment it is typed instead of after the backend answers. Favorites are folders (the
    /// Favorites tab opens every one as a directory), unless the loaded folder says otherwise.
    static func favoriteMatches(_ state: State, query: String) -> [SearchResultItem] {
        let scope = state.searchScope == .everywhere ? "" : state.directoryPath
        return state.favoritePaths.compactMap { favoritePath in
            guard scope.isEmpty || favoritePath.hasPrefix(scope + "/") else { return nil }
            let name = (favoritePath as NSString).lastPathComponent
            guard SearchMatch.matches(query: query, in: name) else { return nil }
            let isDirectory = state.items[id: favoritePath]?.isDirectory ?? true
            return SearchResultItem(
                name: name,
                path: (favoritePath as NSString).deletingLastPathComponent,
                kind: isDirectory ? "dir" : "file"
            )
        }
    }
}

/// The two ways a search answer can be short of the whole truth, as the web client says them.
public enum SearchShortfall: Equatable, Sendable {
    /// The search hit its time budget: these are the results found so far.
    case stoppedEarly
    /// The page is full; there may be more past the first `count`.
    case firstOnly(count: Int)

    init?(_ page: SearchPage) {
        if page.isTruncated {
            self = .stoppedEarly
        } else if page.isComplete {
            return nil
        } else {
            self = .firstOnly(count: page.limit ?? page.items.count)
        }
    }
}
