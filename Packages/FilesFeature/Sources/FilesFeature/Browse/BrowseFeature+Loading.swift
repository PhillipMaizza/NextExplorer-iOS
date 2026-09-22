import ComposableArchitecture
import CoreModels
import FilesClient
import Foundation

extension BrowseFeature {
    /// Fires a background prefetch of `paths` into the offline cache (subfolders of the folder
    /// just loaded, or favorited folders). Best effort and low priority; skips anything cached
    /// recently. `cancelID` scopes it so a later prefetch of the same kind supersedes it while
    /// a different kind runs alongside.
    func prefetch(serverURL: URL, paths: [String], cancelID: CancelID) -> Effect<Action> {
        let paths = paths.filter { !$0.isEmpty }
        guard !paths.isEmpty else { return .none }
        let filesClient = filesClient
        let directoryCacheStore = directoryCacheStore
        return .run(priority: .background) { _ in
            await DirectoryPrefetch.run(
                paths: paths,
                serverURL: serverURL,
                filesClient: filesClient,
                directoryCacheStore: directoryCacheStore
            )
        }
        .cancellable(id: cancelID, cancelInFlight: true)
    }

    /// Recomputes which of the current items are available offline, off the main actor (a per item
    /// disk `stat`, too much for a large listing on the main thread), then commits the ids. A file
    /// counts as available when it's pinned (or inside a pinned folder) OR it's been saved to the
    /// Downloads tab (matched by name within this account's scope); a folder when it's a pinned
    /// root or sits under one.
    func computeOfflineAvailability(_ state: inout State) -> Effect<Action> {
        let items = state.items.elements
        guard !items.isEmpty else {
            state.offlineItemIDs = []
            return .none
        }
        let offlineFileStore = offlineFileStore
        let localDownloadStore = localDownloadStore
        let downloadScope = state.downloadScope
        return .run { send in
            let ids = await Task.detached(priority: .utility) { () -> Set<String> in
                let pinnedPaths = offlineFileStore.pinnedRoots().map(\.path)
                let downloadedNames = Set(((try? localDownloadStore.list(downloadScope)) ?? []).map(\.fileName))
                var result = Set<String>()
                for item in items {
                    // A pinned root, or anything (folder OR file) sitting under one, is available
                    // offline — so browsing into a downloaded folder shows the icon on its files
                    // too, not just the folder.
                    let coveredByPin = pinnedPaths.contains { $0 == item.id || item.id.hasPrefix($0 + "/") }
                    if item.isDirectory {
                        if coveredByPin {
                            result.insert(item.id)
                        }
                    } else if coveredByPin || offlineFileStore.localURL(item) != nil || downloadedNames.contains(item.name) {
                        result.insert(item.id)
                    }
                }
                return result
            }.value
            await send(.offlineAvailabilityComputed(ids))
        }
        .cancellable(id: CancelID.offlineAvailability, cancelInFlight: true)
    }

    func load(_ state: inout State) -> Effect<Action> {
        let hadLoaded = state.phase.hasLoaded
        state.phase = .loading
        let serverURL = state.serverURL
        let directoryPath = state.directoryPath
        let filesClient = filesClient
        // Paint the last saved copy immediately on a first load so there's no skeleton flash
        // while the fetch runs. This is stale-while-revalidate: a successful fetch silently
        // replaces it, and only a failed one (offline) surfaces the "saved copy" banner. So
        // `dataSource` stays `.live` here.
        if !hadLoaded,
           state.items.isEmpty,
           let cached = directoryCacheStore.read(serverURL: serverURL, path: directoryPath)
        {
            state.items = IdentifiedArray(uniqueElements: Self.sortedAlphabetically(cached.items))
            state.access = cached.access
        }
        return .concatenate(
            .run { send in
                try await send(.itemsResponse(apiResult { try await filesClient.browse(serverURL, directoryPath) }))
            },
            .run { send in
                let favorites = try? await filesClient.favorites(serverURL)
                await send(.favoritesResponse(favorites ?? []))
            }
        )
        .cancellable(id: CancelID.load, cancelInFlight: true)
    }

    /// A mutation that edits this folder in place (rename/create/delete/extract/compress) updates
    /// `state.items` but not the on disk listing cache, so an offline revisit, or the first paint
    /// on the next load, would otherwise show the pre mutation listing. Write the corrected
    /// listing straight through with a nil etag, so the next online browse revalidates cleanly (a
    /// 200 that rewrites the real etag) instead of trusting a stamp we invented. Transfer and
    /// upload instead trigger a full refetch, which keeps their listings in sync on its own.
    func syncListingCache(_ state: State) {
        guard let access = state.access else { return }
        directoryCacheStore.write(
            serverURL: state.serverURL,
            path: state.directoryPath,
            result: BrowseResult(items: Array(state.items), access: access, path: state.directoryPath),
            etag: nil,
            fetchedAt: date.now
        )
    }
}
