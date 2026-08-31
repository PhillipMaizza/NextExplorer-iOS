import ComposableArchitecture
import CoreModels
import FilesClient
import Foundation
import Localization
import Testing

@testable import FilesFeature

@MainActor
@Suite
struct MainTabFeatureTests {
    private let serverURL = URL(string: "https://example.com")!
    private let testDate = Date(timeIntervalSince1970: 1_000_000)
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
            $0.date = .constant(self.testDate)
            $0.filesClient.browse = { _, _ in
                BrowseResult(items: [refreshed], access: FileAccess(canRead: true, canWrite: false, canUpload: false, canDelete: false, canShare: false, canDownload: true), path: "")
            }
            $0.filesClient.favorites = { _ in [] }
        }
        store.exhaustivity = .off

        await store.send(.appBecameActive)
        await store.receive(\.browse.root.refreshButtonTapped) {
            $0.browse.root.phase = .loading
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
            $0.favorites.phase = .loading
        }
        await store.receive(\.favorites.favoritesResponse.success) {
            $0.favorites.phase = .loaded
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
            $0.downloads.phase = .loading
        }
        await store.receive(\.downloads.downloadsResponse.success) {
            $0.downloads.phase = .loaded
            $0.downloads.downloads = [download]
        }
    }

    @Test
    func goToSharedTabFromBrowseSwitchesToTheSharedTab() async {
        let store = TestStore(initialState: MainTabFeature.State(serverURL: serverURL, user: user)) {
            MainTabFeature()
        } withDependencies: {
            $0.filesClient.mySharedLinks = { _ in [] }
            $0.filesClient.sharedWithMeLinks = { _ in [] }
            $0.filesClient.shareableUsers = { _ in [] }
        }
        store.exhaustivity = .off

        await store.send(.browse(.delegate(.goToSharedTab))) {
            $0.selectedTab = .shared
        }
        await store.receive(\.shared.refreshRequested)
    }

    @Test
    func goToSharedTabFromTheFavoritesTabAlsoSwitchesTabs() async {
        let store = TestStore(initialState: MainTabFeature.State(serverURL: serverURL, user: user)) {
            MainTabFeature()
        } withDependencies: {
            $0.filesClient.mySharedLinks = { _ in [] }
            $0.filesClient.sharedWithMeLinks = { _ in [] }
            $0.filesClient.shareableUsers = { _ in [] }
        }
        store.exhaustivity = .off

        await store.send(.favorites(.delegate(.goToSharedTab))) {
            $0.selectedTab = .shared
        }
        await store.receive(\.shared.refreshRequested)
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
            $0.favorites.phase = .loading
        }
        await store.receive(\.favorites.favoritesResponse.success) {
            $0.favorites.phase = .loaded
            $0.favorites.favorites = [favorite]
        }
    }

    // MARK: Uploads

    @Test
    func uploadRequestedFromBrowseEnqueuesIntoTheAppWideQueue() async {
        let file = PendingUpload(id: UUID(0), fileURL: URL(fileURLWithPath: "/tmp/a.txt"), fileName: "a.txt", destination: "Inbox")
        let store = TestStore(initialState: MainTabFeature.State(serverURL: serverURL, user: user)) {
            MainTabFeature()
        } withDependencies: {
            $0.date = .constant(self.testDate)
            $0.filesClient.uploadFile = { _, _, name, dest, _ in
                FileItem(name: name, path: dest, dateModified: Date(timeIntervalSince1970: 1), size: 1, kind: "txt")
            }
        }
        store.exhaustivity = .off

        await store.send(.browse(.delegate(.uploadRequested([file]))))
        await store.receive(\.uploads.enqueue)
        #expect(store.state.uploads.jobs.count == 1)
    }

    @Test
    func queueFinishedShowsTheCompletionToastWithAnOpenActionForAnotherFolder() async {
        var state = MainTabFeature.State(serverURL: serverURL, user: user)
        state.selectedTab = .browse
        let store = TestStore(initialState: state) { MainTabFeature() }
        store.exhaustivity = .off

        let summary = UploadsFeature.FinishSummary(
            uploadedCount: 2, failedCount: 0, lastDestination: "Documents/Reports",
            changedPaths: ["Documents/Reports"]
        )
        await store.send(.uploads(.delegate(.queueFinished(summary)))) {
            $0.uploadToast = MainTabFeature.UploadToast(
                message: L10n.Uploads.completeMany(2),
                openDestination: "Documents/Reports"
            )
        }

        await store.send(.openUploadedLocation("Documents/Reports")) {
            $0.uploadToast = nil
            $0.selectedTab = .browse
        }
        await store.receive(\.browse.navigateToDirectory)
    }

    @Test
    func queueFinishedHidesTheOpenActionWhenAlreadyViewingThatFolder() async {
        var state = MainTabFeature.State(serverURL: serverURL, user: user)
        state.selectedTab = .browse
        state.browse.root = BrowseFeature.State(serverURL: serverURL, directoryPath: "Inbox", title: "Inbox")
        let store = TestStore(initialState: state) {
            MainTabFeature()
        } withDependencies: {
            $0.filesClient.browse = { _, _ in
                BrowseResult(items: [], access: FileAccess(canRead: true, canWrite: true, canUpload: true, canDelete: true, canShare: false, canDownload: true), path: "Inbox")
            }
            $0.filesClient.favorites = { _ in [] }
        }
        store.exhaustivity = .off

        let summary = UploadsFeature.FinishSummary(
            uploadedCount: 1, failedCount: 0, lastDestination: "Inbox", changedPaths: ["Inbox"]
        )
        await store.send(.uploads(.delegate(.queueFinished(summary)))) {
            $0.uploadToast = MainTabFeature.UploadToast(message: L10n.Uploads.complete, openDestination: nil)
        }
        // The folder on screen is the one that changed, so it refetches.
        await store.receive(\.browse.root.refreshButtonTapped)
    }

    @Test
    func queueFinishedRefreshesOnlyTheChangedFolderThatIsOnScreen() async {
        var state = MainTabFeature.State(serverURL: serverURL, user: user)
        state.selectedTab = .browse
        state.browse.root = BrowseFeature.State(serverURL: serverURL, directoryPath: "Inbox", title: "Inbox")
        let store = TestStore(initialState: state) {
            MainTabFeature()
        } withDependencies: {
            $0.filesClient.browse = { _, _ in BrowseResult(items: [], access: FileAccess(canRead: true, canWrite: true, canUpload: true, canDelete: true, canShare: false, canDownload: true), path: "") }
            $0.filesClient.favorites = { _ in [] }
        }
        store.exhaustivity = .off

        // Upload landed in a folder nobody is looking at — nothing refetches.
        let summary = UploadsFeature.FinishSummary(
            uploadedCount: 1, failedCount: 0, lastDestination: "Archive/2026", changedPaths: ["Archive/2026"]
        )
        await store.send(.uploads(.delegate(.queueFinished(summary))))
        await store.receive(\.browse.refreshDirectory)
        await store.receive(\.favorites.refreshDirectory)
        #expect(store.state.browse.root.phase != .loading)
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
            $0.downloads.phase = .loading
        }
        await store.receive(\.downloads.downloadsResponse.success) {
            $0.downloads.phase = .loaded
            $0.downloads.downloads = [download]
        }
    }
}
