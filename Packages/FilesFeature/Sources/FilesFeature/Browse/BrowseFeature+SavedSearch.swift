import ComposableArchitecture
import CoreModels
import FilesClient
import Foundation

extension BrowseFeature {
    /// The most saved folders one search reads, so a deep cache cannot stall it.
    static let savedSearchFoldersLimit = 400

    /// Reads the listings saved on the device below the search's folder, once, when a search needs
    /// them: a term too short for the server, or a server that cannot be reached. Saved listings
    /// are a fallback only: a reachable server's answer, or its real error, always
    /// wins over them.
    func loadSavedSearchItemsIfNeeded(_ state: State) -> Effect<Action> {
        guard state.mayAnswerFromSavedListings, state.searchSavedItems == nil else { return .none }
        let directoryCacheStore = directoryCacheStore.bound(to: state.cacheScope)
        let serverURL = state.serverURL
        let base = state.searchBasePath
        return .run { send in
            let items = await Task.detached(priority: .userInitiated) {
                Self.savedItems(under: base, limit: Self.savedSearchFoldersLimit) { path in
                    directoryCacheStore.read(serverURL: serverURL, path: path)?.items
                }
            }.value
            await send(.searchSavedItemsLoaded(items))
        }
        .cancellable(id: CancelID.searchSavedItems, cancelInFlight: true)
    }

    /// Every saved item below `base`, reading at most `limit` folders, and only through folders
    /// whose own listing was saved: a folder never opened is not guessed at.
    nonisolated static func savedItems(under base: String, limit: Int, read: (String) -> [FileItem]?) -> [FileItem] {
        var pending = [base]
        var visited = 0
        var items: [FileItem] = []
        while visited < limit, let path = pending.popLast() {
            visited += 1
            guard let listing = read(path) else { continue }
            items += listing
            pending += listing.filter(\.isDirectory).map(\.id).reversed()
        }
        return items
    }

    /// The saved listings arrived: they join the instant matches while those are what is shown.
    func savedSearchItemsLoaded(_ items: [FileItem], state: inout State) {
        state.searchSavedItems = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        listingChanged(&state)
    }
}
