import ComposableArchitecture
import CoreModels
import FilesClient
import Foundation

extension BrowseFeature {
    /// The most saved folders one search reads, so a deep cache cannot stall it.
    static let savedSearchFoldersLimit = 400
    /// The most saved items one search keeps: each keystroke of a short term matches them all.
    static let savedSearchItemsLimit = 5000

    /// Reads the listings saved on the device below the search's folder, once, when a search needs
    /// them: a term too short for the server, or a server that cannot be reached. Saved listings
    /// are a fallback only: a reachable server's answer, or its real error, always
    /// wins over them.
    func loadSavedSearchItemsIfNeeded(_ state: State) -> Effect<Action> {
        guard state.mayAnswerFromSavedListings, state.searchSavedItems == nil else { return .none }
        let directoryCacheStore = directoryCacheStore.bound(to: state.cacheScope)
        let offlineFileStore = offlineFileStore.pinned(to: state.cacheScope)
        let serverURL = state.serverURL
        let base = state.searchBasePath
        return .run { send in
            let read = Task.detached(priority: .userInitiated) {
                Self.savedItems(
                    under: base,
                    folderLimit: Self.savedSearchFoldersLimit,
                    itemLimit: Self.savedSearchItemsLimit
                ) { path in
                    // The listing kept with a pinned folder backs the shared cache, which evicts.
                    (directoryCacheStore.read(serverURL: serverURL, path: path) ?? offlineFileStore.listing(path))?
                        .items
                }
            }
            // A search that ends or moves stops the read too, not just its answer.
            let items = await withTaskCancellationHandler { await read.value } onCancel: { read.cancel() }
            guard !Task.isCancelled else { return }
            await send(.searchSavedItemsLoaded(items))
        }
        .cancellable(id: CancelID.searchSavedItems, cancelInFlight: true)
    }

    /// Saved items below `base`, reading at most `folderLimit` folders and keeping at most
    /// `itemLimit` items, only through folders whose own listing was saved: a folder never opened
    /// is not guessed at. Stops early when its task is cancelled.
    nonisolated static func savedItems(
        under base: String,
        folderLimit: Int,
        itemLimit: Int,
        read: (String) -> [FileItem]?
    ) -> [FileItem] {
        var pending = [base]
        var visited = 0
        var items: [FileItem] = []
        while visited < folderLimit, items.count < itemLimit, !Task.isCancelled, let path = pending.popLast() {
            visited += 1
            guard let listing = read(path) else { continue }
            items += listing.prefix(itemLimit - items.count)
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
