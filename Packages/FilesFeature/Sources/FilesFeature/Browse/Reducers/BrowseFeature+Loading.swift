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
        cancelID: ScreenCancelID
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
    /// disk `stat`, too much for a large listing on the main thread), then commits the ids. An item
    /// counts as available when it is a pinned root or sits under one, or a file has a stored copy.
    /// `pinned` is the part the user pinned directly.
    func computeOfflineAvailability(_ state: inout State) -> Effect<Action> {
        let items = state.items.elements
        guard !items.isEmpty else {
            state.offlineItemIDs = []
            state.offlinePinnedItemIDs = []
            return .none
        }
        // A detached task drops the account pinned on this task, so the store is bound to it here.
        let offlineFileStore = offlineFileStore.pinned(to: state.cacheScope)
        return .run { send in
            let (all, pinned) = await Task.detached(priority: .utility) {
                OfflineAvailability.classify(
                    items,
                    roots: offlineFileStore.pinnedRoots(),
                    id: \.id,
                    isDirectory: \.isDirectory,
                    hasCopy: { offlineFileStore.localURL($0) != nil }
                )
            }.value
            await send(.offlineAvailabilityComputed(all: all, pinned: pinned))
        }
        .cancellable(id: state.cancelID(.offlineAvailability), cancelInFlight: true)
    }

    /// A mutation that timed out, that a gateway answered for, or whose success answer could not be
    /// read may still have finished on the server, so the folder is refetched to show what really
    /// happened instead of trusting the failure.
    func refetchAfterAmbiguousFailure(_ state: inout State, _ error: FilesClientError) -> Effect<Action> {
        Self.mayHaveAppliedOnServer(error) ? load(&state) : .none
    }

    static func mayHaveAppliedOnServer(_ error: FilesClientError) -> Bool {
        switch error {
        case .timedOut, .decoding:
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
            listingChanged(&state)
            return .none
        }
        if !state.items.isEmpty {
            state.phase = .loaded
            state.fileActionErrorMessage = error.userMessage
            return computeOfflineAvailability(&state)
        }
        state.phase = .failed(error.userMessage)
        return .none
    }

    /// An Offline tab screen lists what is kept on the device, with no request; any other screen
    /// (or an Offline tab folder with nothing kept yet) asks the server.
    func load(_ state: inout State, fromDevice: Bool? = nil) -> Effect<Action> {
        if fromDevice ?? state.isKeptOffline {
            state.phase = .loading
            let offlineFileStore = offlineFileStore.pinned(to: state.cacheScope)
            let directoryPath = state.directoryPath
            return .run { send in
                let roots = offlineFileStore.pinnedRoots()
                await send(.keptListingResolved(offlineFileStore.listing(directoryPath)?.keeping(roots.keeps)))
            }
            .cancellable(id: state.cancelID(.load), cancelInFlight: true)
        }
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
        let offlineFileStore = offlineFileStore.pinned(to: state.cacheScope)
        let paint: Effect<Action> = !hadLoaded && state.items.isEmpty
            ? .run { send in
                guard let cached = directoryCacheStore.read(serverURL: serverURL, path: directoryPath)
                    ?? offlineFileStore.listing(directoryPath)
                else { return }
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
        .cancellable(id: state.cancelID(.load), cancelInFlight: true)
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

extension CachedDirectory {
    /// A saved listing with the kept files added that it lacks (a saved copy older than the
    /// download); whichever exists when only one does, `nil` when neither.
    static func merging(saved: CachedDirectory?, kept: CachedDirectory?) -> CachedDirectory? {
        guard let saved else { return kept }
        guard let kept else { return saved }
        let savedIDs = Set(saved.items.map(\.id))
        return CachedDirectory(
            path: saved.path,
            items: saved.items + kept.items.filter { !savedIDs.contains($0.id) },
            access: saved.access,
            fetchedAt: saved.fetchedAt,
            etag: saved.etag
        )
    }

    /// This listing without the entries `isKept` turns down, such as a file taken off inside a
    /// pinned folder.
    func keeping(_ isKept: (String) -> Bool) -> CachedDirectory {
        CachedDirectory(
            path: path,
            items: items.filter { isKept($0.id) },
            access: access,
            fetchedAt: fetchedAt,
            etag: etag
        )
    }
}

/// Files handed to the system share sheet, identified by the files themselves.
struct KeptFilesShare: Equatable, Identifiable, Sendable {
    let urls: [URL]

    var id: [URL] {
        urls
    }
}
