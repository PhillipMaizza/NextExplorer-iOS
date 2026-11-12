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
struct MainTabFeatureTests {
    private let serverURL = BrowseTestSupport.serverURL
    private let user = User(id: "1", username: "jdoe", email: "jane.doe@example.com", displayName: "Jane Doe", roles: [])

    private func makeState(_ mutate: (inout MainTabFeature.State) -> Void = { _ in }) -> MainTabFeature.State {
        var state = MainTabFeature.State(serverURL: serverURL, user: user)
        mutate(&state)
        return state
    }

    private func makeStore(
        _ state: MainTabFeature.State? = nil,
        configure: (inout DependencyValues) -> Void = { _ in }
    ) -> TestStoreOf<MainTabFeature> {
        TestStore(initialState: state ?? makeState()) {
            MainTabFeature()
        } withDependencies: {
            $0.date = .constant(MockDate.date)
            $0.uuid = .incrementing
            configure(&$0)
        }
    }

    /// A finished change in this window is broadcast to the extra Mac windows.
    private func broadcastFolders(_ state: inout MainTabFeature.State, _ folders: [String]) {
        #if os(macOS)
            state.folderWindowSync = FolderWindowSync(revision: 1, change: .folders(folders), origin: nil)
        #endif
    }

    private nonisolated static let favorite = Favorite(
        id: "1", path: "Photos", label: nil, icon: "star", color: nil, position: 0, createdAt: MockDate.date, updatedAt: MockDate.date
    )

    private nonisolated static let download = LocalDownload(
        url: URL(fileURLWithPath: "/tmp/Documents/Downloads/report.pdf"), fileName: "report.pdf", location: .documents, size: 10, modifiedDate: MockDate.date
    )

    /// A tab action that two screens send the same way, so one test covers both sources.
    struct Source: Sendable, CustomTestStringConvertible {
        let name: String
        let action: MainTabFeature.Action

        var testDescription: String { name }
    }

    // MARK: Settings delegates

    struct SettingsHandOff: Sendable, CustomTestStringConvertible {
        let fromSettings: SettingsFeature.Action.Delegate
        let upward: MainTabFeature.Action.Delegate

        var testDescription: String { "\(upward)" }
    }

    @Test(
        "Account intents from Settings are forwarded upward untouched",
        arguments: [
            SettingsHandOff(fromSettings: .signOutButtonTapped, upward: .signOutButtonTapped),
            SettingsHandOff(fromSettings: .switchAccount("account-2"), upward: .switchAccount("account-2")),
            SettingsHandOff(fromSettings: .removeAccount("account-3"), upward: .removeAccount("account-3")),
            SettingsHandOff(fromSettings: .addAccountRequested, upward: .addAccountRequested),
        ]
    )
    func settingsDelegatesAreForwardedUpward(_ handOff: SettingsHandOff) async {
        let store = makeStore()

        await store.send(.settings(.delegate(handOff.fromSettings)))
        await store.receive(\.delegate, handOff.upward)
    }

    // MARK: Go to Folder and recent folders

    @Test("Go to Folder opens the trimmed path in Browse and closes the dialog")
    func goToFolderOpensTheTrimmedPathInBrowse() async {
        let store = makeStore(makeState { $0.selectedTab = .shared })

        await store.send(.goToFolderPrompted) {
            $0.isGoToFolderPresented = true
        }
        await store.send(.goToFolderRequested(" /Documents/Reports/ ")) {
            $0.isGoToFolderPresented = false
            $0.selectedTab = .browse
        }
        await store.receive(\.browse.navigateToDirectory) {
            $0.browse.path[id: 0] = BrowseFeature.State(serverURL: serverURL, directoryPath: "Documents/Reports", title: "Reports")
            $0.recentFolders = ["Documents/Reports"]
        }
    }

    @Test("A blank Go to Folder path closes the dialog and goes nowhere")
    func aBlankGoToFolderPathDoesNothing() async {
        let store = makeStore(makeState {
            $0.selectedTab = .settings
            $0.isGoToFolderPresented = true
        })

        await store.send(.goToFolderRequested(" / ")) {
            $0.isGoToFolderPresented = false
        }
    }

    @Test("Dismissing Go to Folder closes the dialog")
    func goToFolderDismissedClosesTheDialog() async {
        let store = makeStore(makeState { $0.isGoToFolderPresented = true })

        await store.send(.goToFolderDismissed) {
            $0.isGoToFolderPresented = false
        }
    }

    struct PathCase: Sendable {
        let typed: String
        let expected: String?
    }

    @Test(
        "A typed folder path loses its slashes and spaces, and nothing left means no folder",
        arguments: [
            PathCase(typed: "Documents", expected: "Documents"),
            PathCase(typed: " /Documents/Reports/ ", expected: "Documents/Reports"),
            PathCase(typed: "//Photos//", expected: "Photos"),
            PathCase(typed: "\n/Photos\n", expected: "Photos"),
            PathCase(typed: "My Files/Trip 2026", expected: "My Files/Trip 2026"),
            PathCase(typed: "", expected: nil),
            PathCase(typed: " / ", expected: nil),
            PathCase(typed: "///", expected: nil),
        ]
    )
    func goToFolderPathTrimsWhatTheUserTyped(_ pathCase: PathCase) {
        #expect(MainTabFeature.goToFolderPath(pathCase.typed) == pathCase.expected)
    }

    @Test("Opened folders fill Recent Folders newest first without repeats, and clearing empties it")
    func openedFoldersFillRecentFoldersNewestFirstWithoutRepeats() async {
        let store = makeStore()

        await store.send(.browse(.navigateToDirectory(path: "Documents", title: "Documents"))) {
            $0.browse.path = StackState([BrowseFeature.State(serverURL: serverURL, directoryPath: "Documents", title: "Documents")])
            $0.recentFolders = ["Documents"]
        }
        await store.send(.browse(.navigateToDirectory(path: "Photos/Trip", title: "Trip"))) {
            $0.browse.path = StackState([BrowseFeature.State(serverURL: serverURL, directoryPath: "Photos/Trip", title: "Trip")])
            $0.recentFolders = ["Photos/Trip", "Documents"]
        }
        await store.send(.browse(.navigateToDirectory(path: "Documents", title: "Documents"))) {
            $0.browse.path = StackState([BrowseFeature.State(serverURL: serverURL, directoryPath: "Documents", title: "Documents")])
            $0.recentFolders = ["Documents", "Photos/Trip"]
        }
        await store.send(.recentFoldersCleared) {
            $0.recentFolders = []
        }
    }

    @Test("Recent Folders keep only the newest ten")
    func recentFoldersKeepOnlyTheNewestTen() async {
        let store = makeStore()
        var expected: [String] = []

        for index in 0 ..< 12 {
            let path = "Folder\(index)"
            expected.insert(path, at: 0)
            expected = Array(expected.prefix(10))
            await store.send(.browse(.navigateToDirectory(path: path, title: path))) {
                $0.browse.path = StackState([BrowseFeature.State(serverURL: serverURL, directoryPath: path, title: path)])
                $0.recentFolders = expected
            }
        }

        #expect(store.state.recentFolders == [
            "Folder11", "Folder10", "Folder9", "Folder8", "Folder7", "Folder6", "Folder5", "Folder4", "Folder3", "Folder2",
        ])
    }

    // MARK: Fan out to the tabs

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
            $0.favorites.path.append(BrowseFeature.State(serverURL: serverURL, directoryPath: "Photos", title: "Photos"))
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

    // MARK: Uploads

    @Test("An upload requested from Browse enters the app wide queue and runs against its destination")
    func uploadRequestedFromBrowseEnqueuesIntoTheAppWideQueue() async throws {
        let file = PendingUpload(id: UUID(0), fileURL: URL(fileURLWithPath: "/tmp/a.txt"), fileName: "a.txt", destination: "Inbox")
        let uploaded = LockIsolated<[String]>([])
        let started = AsyncGate()
        let store = makeStore {
            $0.filesClient.uploadFile = { _, url, name, destination, _ in
                uploaded.withValue { $0.append("\(url.path) \(name) \(destination)") }
                started.open()
                try await suspendUntilCancelled()
                throw CancellationError()
            }
        }

        await store.send(.browse(.delegate(.uploadRequested([file]))))
        await store.receive(\.uploads.enqueue) {
            $0.uploads.jobs = [UploadsFeature.UploadJob(
                id: UUID(0), fileURL: URL(fileURLWithPath: "/tmp/a.txt"), fileName: "a.txt", destination: "Inbox", progress: 0, status: .queued
            )]
        }
        await store.receive(\.uploads.startNextIfIdle) {
            $0.uploads.jobs[id: UUID(0)]?.status = .uploading
            $0.uploads.jobs[id: UUID(0)]?.startedAt = MockDate.date
        }
        try await started.wait()
        await store.send(.uploads(.cancelAllTapped)) {
            $0.uploads.jobs = []
        }
        await store.finish()
        #expect(uploaded.value == ["/tmp/a.txt a.txt Inbox"])
    }

    @Test("A finished upload to another folder toasts with an Open action that jumps there")
    func queueFinishedShowsTheCompletionToastWithAnOpenActionForAnotherFolder() async {
        let store = makeStore()
        let summary = UploadsFeature.FinishSummary(
            uploadedCount: 2, failedCount: 0, lastDestination: "Documents/Reports", changedPaths: ["Documents/Reports"]
        )

        await store.send(.uploads(.delegate(.queueFinished(summary)))) {
            $0.uploadToast = MainTabFeature.UploadToast(
                message: L10n.Uploads.completeMany(2),
                openDestination: "Documents/Reports"
            )
            broadcastFolders(&$0, ["Documents/Reports"])
        }
        await store.receive(\.browse.refreshDirectory)
        await store.receive(\.favorites.refreshDirectory)
        await store.send(.openUploadedLocation("Documents/Reports")) {
            $0.uploadToast = nil
            $0.selectedTab = .browse
        }
        await store.receive(\.browse.navigateToDirectory) {
            $0.browse.path[id: 0] = BrowseFeature.State(serverURL: serverURL, directoryPath: "Documents/Reports", title: "Reports")
            $0.recentFolders = ["Documents/Reports"]
        }
    }

    @Test("A finished upload into the folder already on screen toasts without an Open action and refetches it")
    func queueFinishedHidesTheOpenActionWhenAlreadyViewingThatFolder() async {
        let state = makeState {
            $0.browse.root = BrowseFeature.State(serverURL: serverURL, directoryPath: "Inbox", title: "Inbox")
        }
        let store = makeStore(state) { $0.serveEmptyFolders() }
        let summary = UploadsFeature.FinishSummary(
            uploadedCount: 1, failedCount: 0, lastDestination: "Inbox", changedPaths: ["Inbox"]
        )

        await store.send(.uploads(.delegate(.queueFinished(summary)))) {
            $0.uploadToast = MainTabFeature.UploadToast(message: L10n.Uploads.complete, openDestination: nil)
            broadcastFolders(&$0, ["Inbox"])
        }
        await store.receive(\.browse.refreshDirectory)
        await store.receive(\.favorites.refreshDirectory)
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

    @Test("A finished upload into a folder nobody is looking at refetches nothing")
    func queueFinishedRefreshesOnlyTheChangedFolderThatIsOnScreen() async {
        let state = makeState {
            $0.browse.root = BrowseFeature.State(serverURL: serverURL, directoryPath: "Inbox", title: "Inbox")
        }
        let store = makeStore(state)
        let summary = UploadsFeature.FinishSummary(
            uploadedCount: 1, failedCount: 0, lastDestination: "Archive/2026", changedPaths: ["Archive/2026"]
        )

        await store.send(.uploads(.delegate(.queueFinished(summary)))) {
            $0.uploadToast = MainTabFeature.UploadToast(message: L10n.Uploads.complete, openDestination: "Archive/2026")
            broadcastFolders(&$0, ["Archive/2026"])
        }
        await store.receive(\.browse.refreshDirectory)
        await store.receive(\.favorites.refreshDirectory)
    }

    // MARK: Menu bar commands

    @Test("Refresh on the Downloads tab reloads the downloads")
    func refreshSelectedTabRefreshesTheDownloadsTabWhenItIsSelected() async {
        let store = makeStore(makeState { $0.selectedTab = .downloads }) {
            $0.localDownloadStore.list = { _ in [] }
        }

        await store.send(.refreshSelectedTab)
        await store.receive(\.downloads.refreshButtonTapped) {
            $0.downloads.phase = .loading
        }
        await store.receive(\.downloads.downloadsResponse.success) {
            $0.downloads.phase = .loaded
        }
    }

    @Test("Refresh on the Browse tab reloads the folder on screen")
    func refreshSelectedTabRoutesToTheVisibleBrowseFolder() async {
        let store = makeStore { $0.serveEmptyFolders() }

        await store.send(.refreshSelectedTab)
        await store.receive(\.browse.refreshVisibleFolder)
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

    @Test("Refresh on Settings does nothing")
    func refreshSelectedTabDoesNothingOnSettings() async {
        let store = makeStore(makeState { $0.selectedTab = .settings })

        await store.send(.refreshSelectedTab)
    }

    @Test("New Folder is ignored outside Browse")
    func newFolderRequestedIsIgnoredOutsideBrowse() async {
        let store = makeStore(makeState { $0.selectedTab = .favorites })

        await store.send(.newFolderRequested)
    }

    @Test("New Folder at the Browse root is forwarded and then refused, the root is not writable")
    func newFolderRequestedForwardsToBrowse() async {
        let store = makeStore()

        await store.send(.newFolderRequested)
        await store.receive(\.browse.newFolderInVisibleFolder)
    }

    // MARK: Downloads

    @Test(
        "A download requested from either screen is queued app wide and fetched through the client",
        arguments: [
            Source(name: "from Browse", action: .browse(.delegate(.downloadRequested([MainTabFeatureTests.movie])))),
            Source(name: "from Favorites", action: .favorites(.delegate(.downloadRequested([MainTabFeatureTests.movie])))),
        ]
    )
    func downloadRequestedEnqueuesIntoTheAppWideDownloadQueue(_ source: Source) async throws {
        let requested = LockIsolated<[String]>([])
        let started = AsyncGate()
        let store = makeStore {
            $0.filesClient.flushDownloadConnections = {}
            $0.filesClient.downloadItem = { _, item, _ in
                requested.withValue { $0.append(item.id) }
                started.open()
                try await suspendUntilCancelled()
                throw CancellationError()
            }
        }

        await store.send(source.action)
        await store.receive(\.downloadQueue.enqueue) {
            $0.downloadQueue.jobs = [DownloadQueueFeature.DownloadJob(id: UUID(0), item: Self.movie, status: .queued)]
        }
        await store.receive(\.downloadQueue.startNextIfIdle) {
            $0.downloadQueue.jobs[id: UUID(0)]?.status = .downloading
            $0.downloadQueue.jobs[id: UUID(0)]?.startedAt = MockDate.date
        }
        try await started.wait()
        await store.send(.downloadQueue(.cancelAllTapped)) {
            $0.downloadQueue.jobs = []
        }
        await store.finish()
        #expect(requested.value == ["Files/movie.mkv"])
    }

    private nonisolated static let movie = FileItem(name: "movie.mkv", path: "Files", dateModified: MockDate.date, size: 1, kind: "mkv")

    @Test("A drained queue shows the saved toast and Open takes the user to Downloads")
    func downloadQueueFinishedShowsTheSavedToastAndOpenGoesToDownloads() async {
        let store = makeStore { $0.localDownloadStore.list = { _ in [] } }

        await store.send(.downloadQueue(.delegate(.queueFinished(.init(savedCount: 3, failedCount: 0))))) {
            $0.downloadToast = L10n.DownloadQueue.savedMany(3)
        }
        await store.send(.openDownloadsTab) {
            $0.downloadToast = nil
            $0.selectedTab = .downloads
        }
        await store.receive(\.downloads.refreshButtonTapped) {
            $0.downloads.phase = .loading
        }
        await store.receive(\.downloads.downloadsResponse.success) {
            $0.downloads.phase = .loaded
        }
    }

    @Test("A single saved file gets the singular toast")
    func aSingleSavedFileGetsTheSingularToast() async {
        let store = makeStore()

        await store.send(.downloadQueue(.delegate(.queueFinished(.init(savedCount: 1, failedCount: 0))))) {
            $0.downloadToast = L10n.DownloadQueue.savedOne
        }
        await store.send(.dismissDownloadToast) {
            $0.downloadToast = nil
        }
    }

    @Test("A drained queue with a failure shows no toast, the failed bar owns it")
    func downloadQueueFinishedWithFailuresShowsNoToast() async {
        let store = makeStore()

        await store.send(.downloadQueue(.delegate(.queueFinished(.init(savedCount: 1, failedCount: 1)))))
    }

    @Test("A saved download refreshes the Downloads tab and the offline badges on both browse screens")
    func aSavedDownloadRefreshesTheDownloadsTabAndOfflineBadges() async {
        let store = makeStore { $0.localDownloadStore.list = { _ in [] } }

        await store.send(.downloadQueue(.delegate(.itemSaved)))
        await store.receive(\.downloads.refreshButtonTapped) {
            $0.downloads.phase = .loading
        }
        await store.receive(\.browse.offlineAvailabilityChanged)
        await store.receive(\.favorites.offlineAvailabilityChanged)
        await store.receive(\.browse.root.computeOfflineAvailability)
        await store.receive(\.downloads.downloadsResponse.success) {
            $0.downloads.phase = .loaded
        }
    }

    // MARK: Mac sections

    #if os(macOS)
        @Test("A folder stack popping while another section is shown is ignored")
        func aFolderStackPopWhileAnotherSectionIsShownIsIgnored() async {
            var state = makeState()
            state.browse.path.append(BrowseFeature.State(serverURL: serverURL, directoryPath: "Documents", title: "Documents"))
            state.selectedTab = .shared
            let id = state.browse.path.ids[0]
            let store = makeStore(state)

            await store.send(.browse(.path(.popFrom(id: id))))
        }

        @Test("Back in the visible Browse still pops and offers Forward")
        func backInTheVisibleBrowseStillPopsAndOffersForward() async {
            var state = makeState()
            let documents = BrowseFeature.State(serverURL: serverURL, directoryPath: "Documents", title: "Documents")
            state.browse.path.append(documents)
            let id = state.browse.path.ids[0]
            let store = makeStore(state)

            await store.send(.browse(.path(.popFrom(id: id)))) {
                $0.browse.path = StackState()
                $0.browse.forwardStack = [documents]
            }
        }
    #endif
}
