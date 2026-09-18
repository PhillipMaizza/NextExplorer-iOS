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
            state.selectedSearchCategories = []
            return .cancel(id: CancelID.search)
        }

        // Instant client side pre-fill from the already loaded folder, so results appear the
        // moment the user types while the recursive backend search runs. These are name matches
        // in the current folder only — a subset of what either scope's backend search returns, so
        // the authoritative response only ever adds to them (subfolders + content matches).
        // Deliberately does NOT prune `selectedSearchCategories`: the pre-fill sees only this
        // folder, so a selected category the backend subtree contains but this folder lacks would
        // be wrongly cleared. Pruning happens against the authoritative response instead.
        let preliminary = state.items
            .filter { SearchMatch.matches(query: query, in: $0.name) }
            .map { SearchResultItem(name: $0.name, path: $0.path, kind: $0.isDirectory ? "dir" : "file") }
        state.searchResults = IdentifiedArray(Self.sortedAlphabetically(preliminary), id: \.id, uniquingIDsWith: { first, _ in first })
        state.isSearchingRemotely = true

        // Both scopes hit the same recursive, content aware backend endpoint; only the base path
        // differs. "This Folder" scopes to the current directory (its whole subtree); "Everywhere"
        // searches from the root.
        let scopePath = state.searchScope == .everywhere ? "" : state.directoryPath
        let serverURL = state.serverURL
        let filesClient = filesClient
        let clock = clock

        return .run { send in
            try await clock.sleep(for: Constants.searchDebounce)
            try await send(.searchResultsResponse(apiResult {
                try await filesClient.search(serverURL, scopePath, query, Constants.searchLimit)
            }))
        }
        .cancellable(id: CancelID.search, cancelInFlight: true)
    }
}
