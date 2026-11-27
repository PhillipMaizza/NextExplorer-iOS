import ComposableArchitecture
import CoreModels
import DesignSystem
import FilesClient
import FolderPickerFeature
import Foundation
import Localization
import NetworkClient
import ShareUploads
import SwiftUI

extension BrowseFeature {
    /// Loading a folder, its offline copy and the listing responses.
    func reduceListing(_ state: inout State, _ action: Action) -> Effect<Action> {
        switch action {
        case .onAppear:
            // Guard on the phase, not `items.isEmpty`: a folder that is genuinely empty
            // would otherwise refetch on every return to it. A failed load stays put too
            // (retry is the refresh button), so only `.idle` triggers a fetch.
            guard state.phase == .idle else { return .none }
            return load(&state)

        case .refreshButtonTapped:
            return .merge(load(&state), refreshSearch(&state))

        case .computeOfflineAvailability:
            return computeOfflineAvailability(&state)

        case .computeSearchOnDevice:
            return .searchOnDevice(
                (state.searchResults?.elements ?? []) + state.volumeSearch.results,
                ids: &state.searchOnDeviceIDs,
                store: offlineFileStore.pinned(to: state.cacheScope),
                cancelID: state.cancelID(.searchOnDevice)
            ) { .searchOnDeviceComputed($0) }

        case let .searchOnDeviceComputed(ids):
            state.searchOnDeviceIDs = ids
            return .none

        case let .offlineAvailabilityComputed(all, pinned):
            // A search hit open in the preview is not in the listing this was worked out from:
            // its marks stay, or its preview would offer to keep a file that already is.
            var all = all
            var pinned = pinned
            if state.isPreviewOutsideListing, let hit = state.previewItem?.id, state.items[id: hit] == nil {
                if state.offlineItemIDs.contains(hit) {
                    all.insert(hit)
                }
                if state.offlinePinnedItemIDs.contains(hit) {
                    pinned.insert(hit)
                }
            }
            state.offlineItemIDs = all
            state.offlinePinnedItemIDs = pinned
            return .none

        case .offlineRemovalCancelled:
            state.offlineRemoval = nil
            return .none

        case .offlineRemovalConfirmed:
            guard let request = state.offlineRemoval else { return .none }
            state.offlineRemoval = nil
            state.offlineItemIDs.subtract(request.paths)
            state.offlinePinnedItemIDs.subtract(request.paths)
            state.searchOnDeviceIDs = state.searchOnDeviceIDs.filter { !Self.isTakenOff($0, by: request.paths) }
            // A removed folder takes the files kept through it off the device too, except one
            // pinned on its own, which stays.
            state.offlineItemIDs = state.offlineItemIDs.filter { id in
                state.offlinePinnedItemIDs.contains(id) || !request.paths.contains { id.hasPrefix($0 + "/") }
            }
            let unpins = Effect<Action>.merge(
                request.paths.map { .send(.delegate(.offlineUnpinRequested(path: $0))) }
            )
            // The folder on screen came off with its last items: back to where it was opened from.
            if request.emptiedFolderName != nil {
                return .concatenate(
                    unpins,
                    .send(.delegate(.keptFolderEmptied(removedPaths: request.paths)))
                )
            }
            if state.isKeptOffline {
                Self.dropTakenOff(request.paths, from: &state)
                listingChanged(&state)
            }
            return unpins

        case let .keptItemsRemoved(paths):
            guard state.isKeptOffline else { return .none }
            state.offlineItemIDs = state.offlineItemIDs.filter { !Self.isTakenOff($0, by: paths) }
            state.offlinePinnedItemIDs = state.offlinePinnedItemIDs.filter { !Self.isTakenOff($0, by: paths) }
            Self.dropTakenOff(paths, from: &state)
            listingChanged(&state)
            return .none

        case let .offlineToggleTapped(item):
            if state.offlineItemIDs.contains(item.id) || state.searchOnDeviceIDs.contains(item.id) {
                state.offlineRemoval = offlineRemoval(of: [item], state: state)
                return .none
            }
            guard state.actions(for: item).canKeepOffline else { return .none }
            state.offlinePinnedItemIDs.insert(item.id)
            state.offlineItemIDs.insert(item.id)
            if state.searchHit(id: item.id) != nil {
                state.searchOnDeviceIDs.insert(item.id)
            }
            return .send(.delegate(.offlinePinRequested([item])))

        case let .itemsResponse(.success(result)):
            state.phase = .loaded
            state.dataSource = .live
            state.isShowingCachePaint = false
            state.items = IdentifiedArray(
                Self.sortedAlphabetically(result.items),
                id: \.id,
                uniquingIDsWith: { first, _ in first }
            )
            state.access = Self.shownAccess(result.access, isNarrowed: state.isKeptOffline)
            state.shareName = result.shareInfo?.name
            let isShareRoot = ReceivedShareSpace.shareRoot(of: state.directoryPath) == state.directoryPath
            if isShareRoot, let shareName = state.shareName {
                state.title = shareName
            }
            listingChanged(&state)
            return .merge(
                recheckArrivals(&state),
                computeOfflineAvailability(&state),
                loadFolderSizes(state),
                prefetch(
                    serverURL: state.serverURL,
                    paths: result.items.filter(\.isDirectory).map(\.id),
                    scope: state.cacheScope,
                    preferred: state.favoritePaths,
                    shouldIncludePinnedRoots: true,
                    limit: Constants.maxPrefetchedFolders,
                    cancelID: state.cancelID(.prefetchChildren)
                )
            )

        case let .itemsResponse(.failure(error)):
            guard error == .offline else { return failItemsLoad(&state, error) }
            let directoryCacheStore = directoryCacheStore.bound(to: state.cacheScope)
            let offlineFileStore = offlineFileStore.pinned(to: state.cacheScope)
            let serverURL = state.serverURL
            let directoryPath = state.directoryPath
            return .run { send in
                // The saved copy plus whatever is kept on the device, so nothing kept goes missing
                // from a saved copy older than the download.
                let roots = offlineFileStore.pinnedRoots()
                let cached = CachedDirectory.merging(
                    saved: directoryCacheStore.read(serverURL: serverURL, path: directoryPath),
                    kept: offlineFileStore.listing(directoryPath)?.keeping(roots.keeps)
                )
                await send(.offlineListingResolved(cached, error))
            }
            .cancellable(id: state.cancelID(.load))

        case let .offlineListingResolved(cached, error):
            // Offline (server unreachable) with a copy to show: keep it on screen under the
            // "saved copy" banner rather than a blocking error overlay. Prefer the disk copy for its
            // fetched at stamp; otherwise keep whatever the cache first paint (or a prior load this
            // session) already put in `state.items`. Only a real server error, or offline with
            // nothing cached, falls through to the error path.
            state.isShowingCachePaint = false
            if let cached {
                state.phase = .loaded
                state.items = IdentifiedArray(
                    Self.sortedAlphabetically(cached.items),
                    id: \.id,
                    uniquingIDsWith: { first, _ in first }
                )
                state.access = Self.shownAccess(cached.access, isNarrowed: true)
                state.dataSource = .cached(fetchedAt: cached.fetchedAt)
                listingChanged(&state)
                return computeOfflineAvailability(&state)
            } else if !state.items.isEmpty {
                state.phase = .loaded
                state.access = state.access.map { Self.shownAccess($0, isNarrowed: true) }
                state.dataSource = .cached(fetchedAt: date.now)
                return computeOfflineAvailability(&state)
            }
            return failItemsLoad(&state, error)

        case let .keptListingResolved(kept):
            // No kept listing for this folder (not downloaded yet): ask the server like any screen.
            guard let kept else { return load(&state, fromDevice: false) }
            state.phase = .loaded
            state.isShowingCachePaint = false
            state.items = IdentifiedArray(
                Self.sortedAlphabetically(kept.items),
                id: \.id,
                uniquingIDsWith: { first, _ in first }
            )
            state.access = Self.shownAccess(kept.access, isNarrowed: true)
            listingChanged(&state)
            return computeOfflineAvailability(&state)

        case let .cachedListingPainted(cached):
            guard state.phase == .loading, state.items.isEmpty else { return .none }
            state.items = IdentifiedArray(uniqueElements: Self.sortedAlphabetically(cached.items))
            state.access = Self.shownAccess(cached.access, isNarrowed: state.isKeptOffline)
            state.isShowingCachePaint = true
            listingChanged(&state)
            return .none

        case let .serverFeaturesResponse(features):
            state.isPersonalSpaceEnabled = features.isPersonalEnabled
            state.isTrashAvailable = features.trash != nil
            state.isUserVolumesEnabled = features.isUserVolumesEnabled
            let archiveExtensions = features.archiveExtensions ?? []
            state.archiveExtensions = archiveExtensions
            let modeSaved = rememberFolderSizeMode(&state, features.folderSizeMode)
            let jsonCacheStore = jsonCacheStore
            let serverURL = state.serverURL
            let cacheScope = state.cacheScope
            return .merge(
                .run { _ in
                    ListCache.save(
                        jsonCacheStore,
                        Self.personalSpaceCacheNamespace,
                        serverURL: serverURL,
                        scope: cacheScope,
                        value: features.isPersonalEnabled
                    )
                    ListCache.save(
                        jsonCacheStore,
                        Self.userVolumesCacheNamespace,
                        serverURL: serverURL,
                        scope: cacheScope,
                        value: features.isUserVolumesEnabled
                    )
                    ListCache.save(
                        jsonCacheStore,
                        Self.archiveExtensionsCacheNamespace,
                        serverURL: serverURL,
                        scope: cacheScope,
                        value: archiveExtensions
                    )
                },
                modeSaved,
                loadFolderSizes(state)
            )

        case .personalSpaceTapped:
            return .send(.delegate(.openPath(path: PersonalSpace.rootPath, title: L10n.Browse.myFiles)))

        case .trashTapped:
            return .send(.delegate(.openTrashTapped))

        case let .favoritesResponse(favorites):
            state.favoritePaths = Set(favorites.map(\.path))
            state.hasLoadedFavorites = true
            // Browse is the default tab, so its favorites load doubles as a launch time
            // "keep the folders you care about ready offline" pass.
            return prefetch(
                serverURL: state.serverURL,
                paths: Self.favoriteFolderPaths(favorites, knownItems: state.items),
                scope: state.cacheScope,
                limit: Constants.maxPrefetchedFavorites,
                cancelID: state.cancelID(.prefetchFavorites)
            )

        default:
            return .none
        }
    }
}
