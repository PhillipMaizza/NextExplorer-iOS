import ComposableArchitecture
import CoreModels
import FilesClient
import Foundation
import Testing

@testable import FilesFeature

@MainActor
@Suite
struct MainTabFeatureTests {
    private let serverURL = URL(string: "https://example.com")!
    private let user = User(id: "1", username: "jdoe", email: "jane.doe@example.com", displayName: "Jane Doe", roles: [])

    // MARK: Happy path

    @Test
    func tabSelectedUpdatesTheSelectedTab() async {
        let store = TestStore(initialState: MainTabFeature.State(serverURL: serverURL, user: user)) {
            MainTabFeature()
        }

        await store.send(.tabSelected(.favorites)) {
            $0.selectedTab = .favorites
        }
    }

    @Test
    func signOutDelegateFromSettingsIsForwardedUpward() async {
        let store = TestStore(initialState: MainTabFeature.State(serverURL: serverURL, user: user)) {
            MainTabFeature()
        }

        await store.send(.settings(.delegate(.signOutButtonTapped)))
        await store.receive(\.delegate, .signOutButtonTapped)
    }

    // MARK: Edge cases

    @Test
    func initialStateDefaultsToTheBrowseTab() {
        let state = MainTabFeature.State(serverURL: serverURL, user: user)
        #expect(state.selectedTab == .browse)
    }

    @Test
    func appBecameActiveSyncsTheBrowseTabsPathStack() async {
        let refreshed = FileItem(name: "New", path: "", dateModified: Date(), size: 0, kind: "directory")
        let store = TestStore(initialState: MainTabFeature.State(serverURL: serverURL, user: user)) {
            MainTabFeature()
        } withDependencies: {
            $0.filesClient.browse = { _, _ in
                BrowseResult(items: [refreshed], access: FileAccess(canRead: true, canWrite: false, canUpload: false, canDelete: false, canShare: false, canDownload: true), path: "")
            }
            $0.filesClient.favorites = { _ in [] }
        }
        store.exhaustivity = .off

        await store.send(.appBecameActive)
        await store.receive(\.browse.root.refreshButtonTapped) {
            $0.browse.root.isLoading = true
        }
    }

    @Test
    func favoritesChangedFromBrowseRefreshesTheFavoritesTab() async {
        let favorite = Favorite(id: "1", path: "Photos", label: nil, icon: "star", color: nil, position: 0, createdAt: Date(), updatedAt: Date())

        let store = TestStore(initialState: MainTabFeature.State(serverURL: serverURL, user: user)) {
            MainTabFeature()
        } withDependencies: {
            $0.filesClient.favorites = { _ in [favorite] }
        }

        await store.send(.browse(.delegate(.favoritesChanged)))
        await store.receive(\.favorites.refreshButtonTapped) {
            $0.favorites.isLoading = true
        }
        await store.receive(\.favorites.favoritesResponse.success) {
            $0.favorites.isLoading = false
            $0.favorites.favorites = [favorite]
        }
    }

    @Test
    func openDownloadsTappedFromBrowseSwitchesToTheDownloadsTabAndRefreshesIt() async {
        let download = LocalDownload(url: URL(fileURLWithPath: "/tmp/Documents/Downloads/report.pdf"), fileName: "report.pdf", location: .documents, size: 10, modifiedDate: Date())

        let store = TestStore(initialState: MainTabFeature.State(serverURL: serverURL, user: user)) {
            MainTabFeature()
        } withDependencies: {
            $0.localDownloadStore.list = { [download] }
        }

        await store.send(.browse(.delegate(.openDownloadsTapped))) {
            $0.selectedTab = .downloads
        }
        await store.receive(\.downloads.refreshButtonTapped) {
            $0.downloads.isLoading = true
        }
        await store.receive(\.downloads.downloadsResponse.success) {
            $0.downloads.isLoading = false
            $0.downloads.downloads = [download]
        }
    }

    @Test
    func favoritesChangedFromFavoritesRefreshesTheFavoritesTab() async {
        // A favorite toggled from a pushed browse screen *inside* the Favorites tab bubbles
        // up through `FavoritesFeature`'s own delegate — this refreshes the same tab's root
        // list, not Browse's.
        let favorite = Favorite(id: "1", path: "Photos", label: nil, icon: "star", color: nil, position: 0, createdAt: Date(), updatedAt: Date())

        let store = TestStore(initialState: MainTabFeature.State(serverURL: serverURL, user: user)) {
            MainTabFeature()
        } withDependencies: {
            $0.filesClient.favorites = { _ in [favorite] }
        }

        await store.send(.favorites(.delegate(.favoritesChanged)))
        await store.receive(\.favorites.refreshButtonTapped) {
            $0.favorites.isLoading = true
        }
        await store.receive(\.favorites.favoritesResponse.success) {
            $0.favorites.isLoading = false
            $0.favorites.favorites = [favorite]
        }
    }

    @Test
    func openDownloadsTappedFromFavoritesSwitchesToTheDownloadsTabAndRefreshesIt() async {
        let download = LocalDownload(url: URL(fileURLWithPath: "/tmp/Documents/Downloads/report.pdf"), fileName: "report.pdf", location: .documents, size: 10, modifiedDate: Date())

        let store = TestStore(initialState: MainTabFeature.State(serverURL: serverURL, user: user)) {
            MainTabFeature()
        } withDependencies: {
            $0.localDownloadStore.list = { [download] }
        }

        await store.send(.favorites(.delegate(.openDownloadsTapped))) {
            $0.selectedTab = .downloads
        }
        await store.receive(\.downloads.refreshButtonTapped) {
            $0.downloads.isLoading = true
        }
        await store.receive(\.downloads.downloadsResponse.success) {
            $0.downloads.isLoading = false
            $0.downloads.downloads = [download]
        }
    }
}
