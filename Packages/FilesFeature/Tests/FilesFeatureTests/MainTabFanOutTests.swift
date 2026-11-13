import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Localization
import Testing
import TestUtils

@Suite(.isolatedDependencies)
@MainActor
struct MainTabFanOutTests: MainTabTestSupport {
    private nonisolated static let favorite = Favorite(
        id: "1", path: TestFolder.photos, label: nil, icon: "star", color: nil, position: 0, createdAt: MockDate.date,
        updatedAt: MockDate.date
    )

    private nonisolated static let download = LocalDownload(
        url: URL(fileURLWithPath: "/tmp/Documents/Downloads/report.pdf"), fileName: TestFile.report,
        size: 10, modifiedDate: MockDate.date
    )

    @Test("Coming back to the app refreshes the Browse root and checks the pinned folders")
    func appBecameActiveSyncsTheBrowseTabsPathStack() async {
        let store = makeStore { $0.serveEmptyFolders() }

        await store.send(.appBecameActive)
        await store.receive(\.browse.syncPathStack)
        await store.receive(\.favorites.syncPathStack)
        await store.receive(\.uploads.appResumed)
        await store.receive(\.offline.autoSync)
        await store.receive(\.browse.root.refreshButtonTapped) {
            $0.browse.root.phase = .loading
        }
        await store.receive(\.browse.root.itemsResponse.success) {
            $0.browse.root.phase = .loaded
            $0.browse.root.access = BrowseTestSupport.readOnlyAccess
        }
        await store.receive(\.browse.root.favoritesResponse) {
            $0.browse.root.hasLoadedFavorites = true
        }
    }

    @Test("Reconnecting reloads every tab, and the folder pushed in Favorites too, not just the Favorites root")
    func connectivityRestoredRefreshesTheFavoritesTabPushedStackNotJustItsRoot() async throws {
        let state = makeState {
            $0.favorites.path.append(BrowseFeature.State(
                serverURL: serverURL,
                directoryPath: TestFolder.photos,
                title: TestFolder.photos
            ))
        }
        let pushedID = state.favorites.path.ids[0]
        let access = BrowseTestSupport.readOnlyAccess
        let rootListing = AsyncGate()
        let photosListing = AsyncGate()
        let shares = AsyncGate()
        let favoritesCalls = NumberedCalls(capacity: 3)
        let store = makeStore(state) {
            $0.filesClient.browse = { _, path in
                try await (path.isEmpty ? rootListing : photosListing).wait()
                return BrowseResult(items: [], access: access, path: path)
            }
            $0.filesClient.favorites = { _ in
                try await favoritesCalls.park()
                return []
            }
            $0.filesClient.serverFeatures = { _ in throw FilesClientError.offline }
            $0.filesClient.mySharedLinks = { _ in
                try await shares.wait()
                return []
            }
            $0.filesClient.shareableUsers = { _ in [] }
        }

        await store.send(.connectivityRestored)
        await store.receive(\.browse.syncPathStack)
        await store.receive(\.favorites.refreshButtonTapped) {
            $0.favorites.phase = .loading
        }
        await store.receive(\.favorites.syncPathStack)
        await store.receive(\.shared.refreshRequested) {
            $0.shared.phases[.byMe] = .loading
        }
        await store.receive(\.offline.autoSync)
        await store.receive(\.browse.root.refreshButtonTapped) {
            $0.browse.root.phase = .loading
        }
        await store.receive(\.favorites.path[id: pushedID].refreshButtonTapped) {
            $0.favorites.path[id: pushedID]?.phase = .loading
        }

        try await favoritesCalls.arrival(0)
        favoritesCalls.release(0)
        await store.receive(\.favorites.favoritesResponse.success) {
            $0.favorites.phase = .loaded
        }
        shares.open()
        await store.receive(\.shared.sharesResponse) {
            $0.shared.phases[.byMe] = .loaded
            $0.shared.dataSources[.byMe] = .live
        }
        await store.receive(\.shared.usersResponse)
        rootListing.open()
        await store.receive(\.browse.root.itemsResponse.success) {
            $0.browse.root.phase = .loaded
            $0.browse.root.access = access
        }
        try await favoritesCalls.arrival(1)
        photosListing.open()
        await store.receive(\.favorites.path[id: pushedID].itemsResponse.success) {
            $0.favorites.path[id: pushedID]?.phase = .loaded
            $0.favorites.path[id: pushedID]?.access = access
        }
        try await favoritesCalls.arrival(2)
        favoritesCalls.release(1)
        await store.receive(\.browse.root.favoritesResponse) {
            $0.browse.root.hasLoadedFavorites = true
        }
        favoritesCalls.release(2)
        await store.receive(\.favorites.path[id: pushedID].favoritesResponse) {
            $0.favorites.path[id: pushedID]?.hasLoadedFavorites = true
        }
    }

    @Test(
        "A favorite changed on either screen refreshes the Favorites tab",
        arguments: [
            Source(name: "from Browse", action: .browse(.delegate(.favoritesChanged))),
            Source(name: "from Favorites", action: .favorites(.delegate(.favoritesChanged))),
        ]
    )
    func favoritesChangedRefreshesTheFavoritesTab(_ source: Source) async {
        let store = makeStore { $0.filesClient.favorites = { _ in [Self.favorite] } }

        await store.send(source.action)
        await store.receive(\.favorites.refreshButtonTapped) {
            $0.favorites.phase = .loading
        }
        await store.receive(\.favorites.favoritesResponse.success) {
            $0.favorites.phase = .loaded
            $0.favorites.favorites = [Self.favorite]
        }
        await store.receive(\.favorites.offlineAvailabilityComputed)
    }

    @Test(
        "Open Downloads from either screen switches to the Downloads tab and refreshes it",
        arguments: [
            Source(name: "from Browse", action: .browse(.delegate(.openDownloadsTapped))),
            Source(name: "from Favorites", action: .favorites(.delegate(.openDownloadsTapped))),
        ]
    )
    func openDownloadsTappedSwitchesToTheDownloadsTabAndRefreshesIt(_ source: Source) async {
        let store = makeStore { $0.localDownloadStore.list = { _ in [Self.download] } }

        await store.send(source.action) {
            $0.selectedTab = .downloads
        }
        await store.receive(\.downloads.refreshButtonTapped) {
            $0.downloads.phase = .loading
        }
        await store.receive(\.downloads.downloadsResponse.success) {
            $0.downloads.phase = .loaded
            $0.downloads.downloads = [Self.download]
        }
    }

    @Test(
        "View in Shared from either screen switches to the Shared tab and refreshes it",
        arguments: [
            Source(name: "from Browse", action: .browse(.delegate(.goToSharedTab))),
            Source(name: "from Favorites", action: .favorites(.delegate(.goToSharedTab))),
        ]
    )
    func goToSharedTabSwitchesTabs(_ source: Source) async {
        let store = makeStore {
            $0.filesClient.mySharedLinks = { _ in [] }
            $0.filesClient.shareableUsers = { _ in [] }
        }

        await store.send(source.action) {
            $0.selectedTab = .shared
        }
        await store.receive(\.shared.refreshRequested) {
            $0.shared.phases[.byMe] = .loading
        }
        await store.receive(\.shared.sharesResponse) {
            $0.shared.phases[.byMe] = .loaded
            $0.shared.dataSources[.byMe] = .live
        }
        await store.receive(\.shared.usersResponse)
    }
}
