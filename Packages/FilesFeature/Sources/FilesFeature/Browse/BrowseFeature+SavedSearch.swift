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
                Self.savedAndKeptItems(
                    under: base,
                    serverURL: serverURL,
                    directoryCacheStore: directoryCacheStore,
                    offlineFileStore: offlineFileStore
                )
            }
            // A search that ends or moves stops the read too, not just its answer.
            let items = await withTaskCancellationHandler { await read.value } onCancel: { read.cancel() }
            guard !Task.isCancelled else { return }
            await send(.searchSavedItemsLoaded(items))
        }
        .cancellable(id: CancelID.searchSavedItems, cancelInFlight: true)
    }

    /// What the device holds below `base`: the saved listings, and every pinned item below it even when
    /// the folders above it were never saved or their saved copies were dropped. Reads the disk, so call
    /// it off the main actor. Shared by Browse and Favorites search without a connection.
    nonisolated static func savedAndKeptItems(
        under base: String,
        serverURL: URL,
        directoryCacheStore: DirectoryCacheStore,
        offlineFileStore: OfflineFileStore
    ) -> [FileItem] {
        let pinned = offlineFileStore.pinnedRoots().filter { isPath($0.path, below: base) }
        let pinnedFiles = pinned.filter { !$0.isDirectory }.map {
            offlineFileStore.matchingPinnedCopy(pinnedFileItem($0.path))
        }
        let saved = savedItems(
            under: [base] + pinned.filter(\.isDirectory).map(\.path),
            folderLimit: savedSearchFoldersLimit,
            itemLimit: savedSearchItemsLimit
        ) { path in
            // The listing kept with a pinned folder backs the shared cache, which evicts.
            (directoryCacheStore.read(serverURL: serverURL, path: path) ?? offlineFileStore.listing(path))?.items
        }
        // A listing knows the file's real size and date; the pinned stub only fills in files no listing has.
        return saved + pinnedFiles
    }

    /// `items` that `term` matches below `base`, as search results.
    nonisolated static func searchMatches(
        _ items: [FileItem],
        term: SearchTerm,
        below base: String
    ) -> [SearchResultItem] {
        items
            .filter { term.matches(
                name: $0.name,
                relativePath: relativePath($0.id, below: base),
                isDirectory: $0.isDirectory
            ) }
            .map { SearchResultItem(
                name: $0.name,
                path: $0.path,
                kind: SearchResultItem.kind(isDirectory: $0.isDirectory)
            ) }
    }

    /// Saved items below the `starts` folders, reading at most `folderLimit` folders and keeping at
    /// most `itemLimit` items, only through folders whose own listing was saved: a folder never opened
    /// is not guessed at. Each folder is read once, however many starts reach it. Stops early when its
    /// task is cancelled.
    nonisolated static func savedItems(
        under starts: [String],
        folderLimit: Int,
        itemLimit: Int,
        read: (String) -> [FileItem]?
    ) -> [FileItem] {
        var pending = Array(starts.reversed())
        var seen = Set<String>()
        var visited = 0
        var items: [FileItem] = []
        while visited < folderLimit, items.count < itemLimit, !Task.isCancelled, let path = pending.popLast() {
            guard seen.insert(path).inserted else { continue }
            visited += 1
            guard let listing = read(path) else { continue }
            items += listing.prefix(itemLimit - items.count)
            pending += listing.filter(\.isDirectory).map(\.id).reversed()
        }
        return items
    }

    /// Whether `path` is `base` itself or lies below it; the root holds everything.
    nonisolated static func isPath(_ path: String, below base: String) -> Bool {
        base.isEmpty || path == base || path.hasPrefix(base + "/")
    }

    /// A pinned file as a listing would show it; `matchingPinnedCopy` fills in its kept size and date.
    nonisolated static func pinnedFileItem(_ path: String) -> FileItem {
        let name = (path as NSString).lastPathComponent
        return FileItem(
            name: name,
            path: (path as NSString).deletingLastPathComponent,
            dateModified: .distantPast,
            size: 0,
            kind: (name as NSString).pathExtension.lowercased()
        )
    }

    /// The saved listings arrived: they join the instant matches while those are what is shown.
    func savedSearchItemsLoaded(_ items: [FileItem], state: inout State) {
        state.searchSavedItems = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        listingChanged(&state)
    }
}
