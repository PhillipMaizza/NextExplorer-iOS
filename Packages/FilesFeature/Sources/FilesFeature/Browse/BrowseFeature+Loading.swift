import ComposableArchitecture
import CoreModels
import FilesClient
import FolderPickerFeature
import Foundation

extension BrowseFeature {
    /// Fires a background prefetch of `paths` into the offline cache (subfolders of the folder
    /// just loaded, or favorited folders). Best effort and low priority; skips anything cached
    /// recently. `cancelID` scopes it so a later prefetch of the same kind supersedes it while
    /// a different kind runs alongside. The pinned roots are read inside the effect, never on the
    /// reducer's main actor, and `limit` caps this kind on its own budget.
    func prefetch(
        serverURL: URL,
        paths: [String],
        scope: String,
        preferred: Set<String> = [],
        includesPinnedRoots: Bool = false,
        limit: Int,
        cancelID: CancelID
    ) -> Effect<Action> {
        guard !connectivity.isMetered() else { return .none }
        let paths = paths.filter { !$0.isEmpty }
        guard !paths.isEmpty else { return .none }
        let filesClient = filesClient
        let directoryCacheStore = directoryCacheStore.bound(to: scope)
        let offlineFileStore = offlineFileStore
        return .run(priority: .background) { _ in
            var preferred = preferred
            if includesPinnedRoots {
                preferred.formUnion(offlineFileStore.pinnedRoots().map(\.path))
            }
            await DirectoryPrefetch.run(
                paths: Array(BrowseFeature.prefetchOrder(paths, preferred: preferred).prefix(limit)),
                serverURL: serverURL,
                filesClient: filesClient,
                directoryCacheStore: directoryCacheStore
            )
        }
        .cancellable(id: cancelID, cancelInFlight: true)
    }

    /// Puts favorited and pinned folders first, keeping the listing order (nearest first) within each
    /// group, so the prefetch cap spends its budget on the folders the user is likeliest to open.
    static func prefetchOrder(_ paths: [String], preferred: Set<String>) -> [String] {
        paths.filter { preferred.contains($0) } + paths.filter { !preferred.contains($0) }
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
                    // offline: so browsing into a downloaded folder shows the icon on its files
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

    /// A mutation that timed out may still have finished on the server, so the folder is refetched to
    /// show what really happened instead of trusting the failure.
    func refetchAfterTimeout(_ state: inout State, _ error: FilesClientError) -> Effect<Action> {
        error == .timedOut ? load(&state) : .none
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
           let cached = directoryCacheStore.bound(to: state.cacheScope).read(serverURL: serverURL, path: directoryPath)
        {
            state.items = IdentifiedArray(uniqueElements: Self.sortedAlphabetically(cached.items))
            state.access = cached.access
            state.isShowingCachePaint = true
        }
        let features: Effect<Action> = directoryPath.isEmpty
            ? .run { send in
                // Offline or an older server: keep whatever the last successful answer was.
                guard let features = try? await filesClient.serverFeatures(serverURL) else { return }
                await send(.serverFeaturesResponse(features))
            }
            : .none
        return .merge(
            .concatenate(
                .run { send in
                    try await send(.itemsResponse(apiResult { try await filesClient.browse(serverURL, directoryPath) }))
                },
                .run { send in
                    // A failed fetch sends nothing: an empty answer would turn every star off and make
                    // the next tap add a favorite that already exists instead of removing it.
                    guard let favorites = try? await filesClient.favorites(serverURL) else { return }
                    await send(.favoritesResponse(favorites))
                }
            ),
            features
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
        directoryCacheStore.bound(to: state.cacheScope).write(
            serverURL: state.serverURL,
            path: state.directoryPath,
            result: BrowseResult(items: Array(state.items), access: access, path: state.directoryPath),
            etag: nil,
            fetchedAt: date.now
        )
    }
}
