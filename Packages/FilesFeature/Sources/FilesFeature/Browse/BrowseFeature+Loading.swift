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
    /// reducer's main actor, and `limit` caps this kind on its own budget, spent on stale folders only.
    func prefetch(
        serverURL: URL,
        paths: [String],
        scope: String,
        preferred: Set<String> = [],
        shouldIncludePinnedRoots: Bool = false,
        limit: Int,
        cancelID: CancelID
    ) -> Effect<Action> {
        guard !connectivity.isMetered() else { return .none }
        let paths = paths.filter { !$0.isEmpty }
        guard !paths.isEmpty else { return .none }
        let filesClient = filesClient
        let now = date.now
        let directoryCacheStore = directoryCacheStore.bound(to: scope)
        let offlineFileStore = offlineFileStore
        return .run(priority: .background) { _ in
            var preferred = preferred
            if shouldIncludePinnedRoots {
                preferred.formUnion(offlineFileStore.pinnedRoots().map(\.path))
            }
            await DirectoryPrefetch.run(
                paths: BrowseFeature.prefetchOrder(paths, preferred: preferred),
                limit: limit,
                now: now,
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

    /// The favorites worth warming: a favorite the listing on screen shows as a file is skipped (a
    /// favorite carries no kind, and listing a file path only wastes a request); one whose kind is
    /// unknown is kept.
    static func favoriteFolderPaths(_ favorites: [Favorite], knownItems: IdentifiedArrayOf<FileItem>) -> [String] {
        favorites.map(\.path).filter { knownItems[id: $0]?.isDirectory ?? true }
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

    /// A mutation that timed out, or that a gateway answered for, may still have finished on the
    /// server, so the folder is refetched to show what really happened instead of trusting the failure.
    func refetchAfterAmbiguousFailure(_ state: inout State, _ error: FilesClientError) -> Effect<Action> {
        Self.mayHaveAppliedOnServer(error) ? load(&state) : .none
    }

    static func mayHaveAppliedOnServer(_ error: FilesClientError) -> Bool {
        switch error {
        case .timedOut:
            true
        case let .server(statusCode), let .serverMessage(statusCode, _):
            Constants.ambiguousMutationStatuses.contains(statusCode)
        default:
            false
        }
    }

    /// A browse failure that is not an offline fallback. Items still on screen from the cache first
    /// paint, or from an earlier offline fallback, were never confirmed by the server, and a real error
    /// (404, 403, 500) says they may be wrong: show the error instead. A refresh that fails on a folder
    /// already showing live items keeps them and reports the error as a toast, like the Favorites and
    /// Shares tabs, rather than blanking the list.
    func failItemsLoad(_ state: inout State, _ error: FilesClientError) -> Effect<Action> {
        if state.isShowingCachePaint || state.dataSource != .live {
            state.isShowingCachePaint = false
            state.dataSource = .live
            state.items = []
            state.access = nil
            state.phase = .failed(error.userMessage)
            return .none
        }
        if !state.items.isEmpty {
            state.phase = .loaded
            state.fileActionErrorMessage = error.userMessage
            return .merge(search(&state), computeOfflineAvailability(&state))
        }
        state.phase = .failed(error.userMessage)
        return .none
    }

    func load(_ state: inout State) -> Effect<Action> {
        let hadLoaded = state.phase.hasLoaded
        state.phase = .loading
        let serverURL = state.serverURL
        let directoryPath = state.directoryPath
        let filesClient = filesClient
        // Paint the last saved copy on a first load so there's no skeleton flash while the fetch
        // runs. This is stale while revalidate: a successful fetch silently replaces it, and only a
        // failed one (offline) surfaces the "saved copy" banner. So `dataSource` stays `.live` here.
        // The disk read runs beside the fetch, off the main actor, and is dropped if the fetch won.
        let directoryCacheStore = directoryCacheStore.bound(to: state.cacheScope)
        let paint: Effect<Action> = !hadLoaded && state.items.isEmpty
            ? .run { send in
                guard let cached = directoryCacheStore.read(serverURL: serverURL, path: directoryPath) else { return }
                await send(.cachedListingPainted(cached))
            }
            : .none
        let features: Effect<Action> = directoryPath.isEmpty
            ? .run { send in
                // Offline or an older server: keep whatever the last successful answer was.
                guard let features = try? await filesClient.serverFeatures(serverURL) else { return }
                await send(.serverFeaturesResponse(features))
            }
            : .none
        return .merge(
            paint,
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
