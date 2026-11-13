import ComposableArchitecture
import CoreModels
import FilesClient
import FolderPickerFeature
import Foundation

extension BrowseFeature {
    /// Both scopes run a recursive, content aware `/api/search` (only the base path differs).
    /// Typing is debounced so a burst of keystrokes fires one request; a tap (scope) is a
    /// decision already made and asks at once. A client side prefill from the already loaded
    /// folder paints instantly while that request is in flight.
    func search(_ state: inout State, isDebounced: Bool = true) -> Effect<Action> {
        // Trim like the backend does before its own empty check, so an all whitespace query is
        // treated as empty rather than pre-filling everything and 400ing on a blank `q`.
        let term = SearchTerm(state.searchQuery)
        let query = term.text
        guard !term.isEmpty else {
            state.searchResults = nil
            state.searchAnsweredTerm = nil
            state.searchPhase = .idle
            state.searchShortfall = nil
            state.selectedSearchCategories = []
            state.searchScope = .thisFolder
            return .cancel(id: CancelID.search)
        }

        // The server only searches from three characters on; until then the instant matches stand.
        guard term.isSearchable else {
            showInstantMatches(&state, query: query)
            state.searchPhase = .idle
            state.searchShortfall = nil
            return .cancel(id: CancelID.search)
        }
        // An earlier answer stays on screen until this term's arrives, as the web client keeps
        // its results, so the list never shrinks to the local matches and grows back on each
        // keystroke. With no answer to show, the instant matches paint at once.
        if !state.isShowingSearchAnswer {
            showInstantMatches(&state, query: query)
        }
        state.searchPhase = .loading
        return fetchSearchResults(state, isDebounced: isDebounced)
    }

    /// Instant client side matches from the already loaded folder and the favorites, so results
    /// appear the moment the user types while the recursive backend search runs. Name matches
    /// only: a subset of what either scope's backend search returns, so the authoritative
    /// response only ever adds to them (subfolders and content matches).
    static func instantMatches(_ state: State, query: String) -> IdentifiedArrayOf<SearchResultItem> {
        let term = SearchTerm(query)
        let base = state.searchBasePath
        let inFolder = state.items
            .filter { term.matches(name: $0.name, relativePath: relativePath($0.id, below: base), isDirectory: $0.isDirectory) }
            .map { SearchResultItem(name: $0.name, path: $0.path, kind: SearchResultItem.kind(isDirectory: $0.isDirectory)) }
        // In the server's order, so its answer lands without shuffling what is already there.
        let results = term.ranked(inFolder + favoriteMatches(state, term: term))
        return IdentifiedArray(results, id: \.id, uniquingIDsWith: { first, _ in first })
    }

    /// `path` as the server sees it below the search's folder: the whole path from the root.
    static func relativePath(_ path: String, below base: String) -> String {
        guard !base.isEmpty, path.hasPrefix(base + "/") else { return path }
        return String(path.dropFirst(base.count + 1))
    }

    /// Deliberately does NOT prune `selectedSearchCategories`: the instant matches see only this
    /// folder, so a selected category the backend subtree contains but this folder lacks would be
    /// wrongly cleared. Pruning happens against the authoritative response instead.
    private func showInstantMatches(_ state: inout State, query: String) {
        state.searchResults = Self.instantMatches(state, query: query)
        state.searchAnsweredTerm = nil
    }

    /// A listing of the folder on screen landed (live, the saved copy, a refresh, a failure that
    /// cleared it). It feeds only the instant matches, while they are what is on screen. A server
    /// search is left alone: its recursive answer is not this listing, and running it again reset
    /// the results to the local matches and restarted the wait with nothing typed.
    func listingChanged(_ state: inout State) {
        let term = SearchTerm(state.searchQuery)
        guard !term.isEmpty, !state.isShowingSearchAnswer else { return }
        showInstantMatches(&state, query: term.text)
    }

    /// An explicit refresh while searching (pull to refresh, the toolbar, Retry) refreshes what is
    /// on screen, the results: at once, without the typing wait, keeping them meanwhile.
    func refreshSearch(_ state: inout State) -> Effect<Action> {
        guard SearchTerm(state.searchQuery).isSearchable else { return .none }
        state.searchPhase = .loading
        return fetchSearchResults(state, isDebounced: false)
    }

    /// The server search on its own, without the instant prefill: Show more widens the answer
    /// already on screen rather than starting over from the local matches.
    func fetchSearchResults(_ state: State, isDebounced: Bool) -> Effect<Action> {
        let query = SearchTerm(state.searchQuery).text
        // Both scopes hit the same recursive, content aware backend endpoint; only the base path
        // differs. "This Folder" scopes to the current directory (its whole subtree); "Everywhere"
        // searches from the root.
        let scopePath = state.searchBasePath
        let serverURL = state.serverURL
        let filesClient = filesClient
        let clock = clock
        let limit = state.searchLimit

        return .run { send in
            if isDebounced {
                try await clock.sleep(for: FilesClient.searchDebounce)
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
    static func favoriteMatches(_ state: State, term: SearchTerm) -> [SearchResultItem] {
        let base = state.searchBasePath
        return state.favoritePaths.compactMap { favoritePath in
            guard base.isEmpty || favoritePath.hasPrefix(base + "/") else { return nil }
            let name = (favoritePath as NSString).lastPathComponent
            let isDirectory = state.items[id: favoritePath]?.isDirectory ?? true
            guard term.matches(name: name, relativePath: relativePath(favoritePath, below: base), isDirectory: isDirectory) else { return nil }
            return SearchResultItem(
                name: name,
                path: (favoritePath as NSString).deletingLastPathComponent,
                kind: SearchResultItem.kind(isDirectory: isDirectory)
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
