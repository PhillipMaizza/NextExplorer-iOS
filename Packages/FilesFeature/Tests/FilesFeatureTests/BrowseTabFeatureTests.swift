import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Testing

@MainActor
struct BrowseTabFeatureTests {
    private let serverURL = URL(string: "https://example.com")!

    // MARK: Happy path

    @Test
    func openingAFolderFromTheRootPushesItOntoThePathStack() async {
        let item = FileItem(name: "Photos", path: "", dateModified: Date(), size: 0, kind: "directory")
        let store = TestStore(initialState: BrowseTabFeature.State(serverURL: serverURL)) {
            BrowseTabFeature()
        }

        await store.send(.root(.delegate(.openFolder(item)))) {
            $0.path.append(BrowseFeature.State(serverURL: serverURL, directoryPath: item.id, title: item.name))
        }
    }

    @Test
    func openingAFolderFromAPushedScreenPushesAnotherLevel() async {
        let root = FileItem(name: "Photos", path: "", dateModified: Date(), size: 0, kind: "directory")
        var state = BrowseTabFeature.State(serverURL: serverURL)
        state.path.append(BrowseFeature.State(serverURL: serverURL, directoryPath: root.id, title: root.name))
        let nested = FileItem(name: "Vacation", path: "Photos", dateModified: Date(), size: 0, kind: "directory")

        let store = TestStore(initialState: state) {
            BrowseTabFeature()
        }

        await store.send(.path(.element(id: 0, action: .delegate(.openFolder(nested))))) {
            $0.path.append(BrowseFeature.State(serverURL: serverURL, directoryPath: nested.id, title: nested.name))
        }
    }

    @Test
    func navigatingToANonEmptyPathReplacesTheEntirePathStack() async {
        var state = BrowseTabFeature.State(serverURL: serverURL)
        state.path.append(BrowseFeature.State(serverURL: serverURL, directoryPath: "A", title: "A"))
        state.path.append(BrowseFeature.State(serverURL: serverURL, directoryPath: "A/B", title: "B"))

        let store = TestStore(initialState: state) {
            BrowseTabFeature()
        }

        await store.send(.navigateToDirectory(path: "Photos", title: "Photos")) {
            $0.path = StackState([BrowseFeature.State(serverURL: serverURL, directoryPath: "Photos", title: "Photos")])
        }
    }

    private func pasteScenario(listsCopyAfterFetches lag: Int) -> (BrowseTabFeature.State, TestStoreOf<BrowseTabFeature>, LockIsolated<Int>) {
        let misc = FileItem(name: "Misc", path: "Docs", dateModified: Date(timeIntervalSince1970: 1), size: 0, kind: "directory")
        let copy = FileItem(name: "Misc (2)", path: "Docs", dateModified: Date(timeIntervalSince1970: 2), size: 0, kind: "directory")
        let access = FileAccess(canRead: true, canWrite: true, canUpload: true, canDelete: true, canShare: true, canDownload: true)
        var docs = BrowseFeature.State(serverURL: serverURL, directoryPath: "Docs", title: "Docs")
        docs.items = [misc]
        docs.phase = .loaded
        docs.access = access
        docs.$clipboard.withLock { $0 = FileClipboard(items: [misc], operation: .copy) }
        var state = BrowseTabFeature.State(serverURL: serverURL)
        state.path.append(docs)
        let didCopy = LockIsolated(false)
        let fetchesAfterCopy = LockIsolated(0)

        let store = TestStore(initialState: state) {
            BrowseTabFeature()
        } withDependencies: {
            $0.filesClient.transferItems = { _, _, destination, _ in
                didCopy.setValue(true)
                return TransferResult(destination: destination, items: [.init(from: "Docs/Misc", to: "Docs/Misc (2)")])
            }
            $0.filesClient.browse = { _, path in
                guard path == "Docs" else { return BrowseResult(items: [], access: access, path: path) }
                guard didCopy.value else { return BrowseResult(items: [misc], access: access, path: path) }
                fetchesAfterCopy.withValue { $0 += 1 }
                let listed = fetchesAfterCopy.value > lag
                return BrowseResult(items: listed ? [misc, copy] : [misc], access: access, path: path)
            }
            $0.filesClient.favorites = { _ in [] }
            $0.filesClient.serverFeatures = { _ in throw FilesClientError.offline }
            $0.directoryCacheStore.remove = { _, _ in }
            $0.continuousClock = ImmediateClock()
        }
        store.exhaustivity = .off
        return (state, store, fetchesAfterCopy)
    }

    @Test
    func pastingAFolderIntoItsOwnFolderShowsTheCopyWithoutARefresh() async {
        let (_, store, _) = pasteScenario(listsCopyAfterFetches: 0)

        await store.send(.path(.element(id: 0, action: .pasteTapped(keepItemsAfterCopy: false))))
        await store.finish(timeout: .seconds(10))
        await store.skipReceivedActions()
        #expect(store.state.path[id: 0]?.items.map(\.name) == ["Misc", "Misc (2)"])
        #expect(store.state.path[id: 0]?.awaitedArrivalIDs.isEmpty == true)
    }

    @Test
    func aCopyTheServerListsLateIsRefetchedUntilItAppears() async {
        let (_, store, fetches) = pasteScenario(listsCopyAfterFetches: 2)

        await store.send(.path(.element(id: 0, action: .pasteTapped(keepItemsAfterCopy: false))))
        await store.finish(timeout: .seconds(10))
        await store.skipReceivedActions()
        #expect(store.state.path[id: 0]?.items.map(\.name) == ["Misc", "Misc (2)"])
        #expect(fetches.value == 3)
        #expect(store.state.path[id: 0]?.awaitedArrivalIDs.isEmpty == true)
    }

    // MARK: Edge cases

    @Test
    func navigatingToAnEmptyPathClearsTheStackAndStaysOnRoot() async {
        var state = BrowseTabFeature.State(serverURL: serverURL)
        state.path.append(BrowseFeature.State(serverURL: serverURL, directoryPath: "A", title: "A"))

        let store = TestStore(initialState: state) {
            BrowseTabFeature()
        }

        await store.send(.navigateToDirectory(path: "", title: "Home")) {
            $0.path = StackState()
        }
    }

    @Test
    func openPathDelegateFromTheRootForwardsToNavigateToDirectory() async {
        // Exhaustivity off: the pushed `BrowseFeature.State` gets a fresh `StackElementID`
        // whose exact value isn't reproducible in a `receive`-triggered assertion closure
        // (unlike `send`, TCA's test generator snapshotting doesn't line the two up here) —
        // asserting the resulting path's content is what actually matters.
        let store = TestStore(initialState: BrowseTabFeature.State(serverURL: serverURL)) {
            BrowseTabFeature()
        }
        store.exhaustivity = .off

        await store.send(.root(.delegate(.openPath(path: "Photos", title: "Photos"))))
        await store.receive(\.navigateToDirectory)

        #expect(store.state.path.map(\.directoryPath) == ["Photos"])
        #expect(store.state.path.map(\.title) == ["Photos"])
    }

    @Test
    func openPathDelegateFromAPushedScreenForwardsToNavigateToDirectory() async {
        var state = BrowseTabFeature.State(serverURL: serverURL)
        state.path.append(BrowseFeature.State(serverURL: serverURL, directoryPath: "A", title: "A"))

        let store = TestStore(initialState: state) {
            BrowseTabFeature()
        }

        await store.send(.path(.element(id: 0, action: .delegate(.openPath(path: "", title: "Home")))))
        await store.receive(.navigateToDirectory(path: "", title: "Home")) {
            $0.path = StackState()
        }
    }

    @Test
    func navigatingToTheSamePathTwiceStillReplacesTheStackWithAFreshBrowseFeatureState() async {
        // Regression guard: a breadcrumb re-tap on the currently-open folder should still
        // reset the stack to a single fresh element, not leave stale nested screens behind.
        var state = BrowseTabFeature.State(serverURL: serverURL)
        state.path.append(BrowseFeature.State(serverURL: serverURL, directoryPath: "Photos", title: "Photos"))
        state.path.append(BrowseFeature.State(serverURL: serverURL, directoryPath: "Photos/Old", title: "Old"))

        let store = TestStore(initialState: state) {
            BrowseTabFeature()
        }

        await store.send(.navigateToDirectory(path: "Photos", title: "Photos")) {
            $0.path = StackState([BrowseFeature.State(serverURL: serverURL, directoryPath: "Photos", title: "Photos")])
        }
    }

    // MARK: Sync on app open

    @Test
    func syncPathStackRefreshesOnlyTheRootWhenNoFolderIsPushed() async {
        let refreshed = FileItem(name: "New", path: "", dateModified: Date(), size: 0, kind: "directory")
        let store = TestStore(initialState: BrowseTabFeature.State(serverURL: serverURL)) {
            BrowseTabFeature()
        } withDependencies: {
            $0.filesClient.browse = { _, _ in
                BrowseResult(items: [refreshed], access: FileAccess(canRead: true, canWrite: false, canUpload: false, canDelete: false, canShare: false, canDownload: true), path: "")
            }
            $0.filesClient.favorites = { _ in [] }
        }
        store.exhaustivity = .off

        await store.send(.syncPathStack)
        await store.receive(\.root.refreshButtonTapped) {
            $0.root.phase = .loading
        }
    }

    @Test
    func syncPathStackRefreshesTheRootAndEveryPushedSubfolder() async {
        var state = BrowseTabFeature.State(serverURL: serverURL)
        state.path.append(BrowseFeature.State(serverURL: serverURL, directoryPath: "Photos", title: "Photos"))
        state.path.append(BrowseFeature.State(serverURL: serverURL, directoryPath: "Photos/Old", title: "Old"))
        let refreshed = FileItem(name: "New", path: "", dateModified: Date(), size: 0, kind: "directory")

        let store = TestStore(initialState: state) {
            BrowseTabFeature()
        } withDependencies: {
            $0.filesClient.browse = { _, _ in
                BrowseResult(items: [refreshed], access: FileAccess(canRead: true, canWrite: false, canUpload: false, canDelete: false, canShare: false, canDownload: true), path: "")
            }
            $0.filesClient.favorites = { _ in [] }
        }
        store.exhaustivity = .off
        let pathIDs = state.path.ids

        await store.send(.syncPathStack)
        await store.receive(\.root.refreshButtonTapped) {
            $0.root.phase = .loading
        }
        await store.receive(\.path[id: pathIDs[0]].refreshButtonTapped) {
            $0.path[id: pathIDs[0]]?.phase = .loading
        }
        await store.receive(\.path[id: pathIDs[1]].refreshButtonTapped) {
            $0.path[id: pathIDs[1]]?.phase = .loading
        }
    }

    @Test
    func directoryContentsChangedFromAPushedScreenReSyncsTheWholeStack() async {
        var state = BrowseTabFeature.State(serverURL: serverURL)
        state.path.append(BrowseFeature.State(serverURL: serverURL, directoryPath: "Photos", title: "Photos"))
        let refreshed = FileItem(name: "New", path: "", dateModified: Date(), size: 0, kind: "directory")

        let store = TestStore(initialState: state) {
            BrowseTabFeature()
        } withDependencies: {
            $0.filesClient.browse = { _, _ in
                BrowseResult(items: [refreshed], access: FileAccess(canRead: true, canWrite: true, canUpload: true, canDelete: true, canShare: false, canDownload: true), path: "")
            }
            $0.filesClient.favorites = { _ in [] }
        }
        store.exhaustivity = .off
        let pathIDs = state.path.ids

        await store.send(.path(.element(id: pathIDs[0], action: .delegate(.directoryContentsChanged))))
        await store.receive(\.syncPathStack)
        await store.receive(\.root.refreshButtonTapped)
        await store.receive(\.path[id: pathIDs[0]].refreshButtonTapped)
    }

    // MARK: Favorites-changed delegate bubbling

    @Test
    func favoritesChangedFromTheRootBubblesUpAsADelegate() async {
        let store = TestStore(initialState: BrowseTabFeature.State(serverURL: serverURL)) {
            BrowseTabFeature()
        }

        await store.send(.root(.delegate(.favoritesChanged)))
        await store.receive(.delegate(.favoritesChanged))
    }

    @Test
    func favoritesChangedFromAPushedScreenAlsoBubblesUpAsADelegate() async {
        var state = BrowseTabFeature.State(serverURL: serverURL)
        state.path.append(BrowseFeature.State(serverURL: serverURL, directoryPath: "Photos", title: "Photos"))

        let store = TestStore(initialState: state) {
            BrowseTabFeature()
        }

        await store.send(.path(.element(id: 0, action: .delegate(.favoritesChanged))))
        await store.receive(.delegate(.favoritesChanged))
    }

    // MARK: Open-downloads delegate bubbling

    @Test
    func openDownloadsTappedFromTheRootBubblesUpAsADelegate() async {
        let store = TestStore(initialState: BrowseTabFeature.State(serverURL: serverURL)) {
            BrowseTabFeature()
        }

        await store.send(.root(.delegate(.openDownloadsTapped)))
        await store.receive(.delegate(.openDownloadsTapped))
    }

    @Test
    func openDownloadsTappedFromAPushedScreenAlsoBubblesUpAsADelegate() async {
        var state = BrowseTabFeature.State(serverURL: serverURL)
        state.path.append(BrowseFeature.State(serverURL: serverURL, directoryPath: "Photos", title: "Photos"))

        let store = TestStore(initialState: state) {
            BrowseTabFeature()
        }

        await store.send(.path(.element(id: 0, action: .delegate(.openDownloadsTapped))))
        await store.receive(.delegate(.openDownloadsTapped))
    }

    @Test
    func goToSharedTabBubblesUpAsADelegate() async {
        let store = TestStore(initialState: BrowseTabFeature.State(serverURL: serverURL)) {
            BrowseTabFeature()
        }

        await store.send(.root(.delegate(.goToSharedTab)))
        await store.receive(.delegate(.goToSharedTab))
    }

    // MARK: Menu bar commands

    private nonisolated static let readOnlyAccess = FileAccess(canRead: true, canWrite: false, canUpload: false, canDelete: false, canShare: false, canDownload: true)

    @Test
    func refreshVisibleFolderRefreshesTheRootWhenNothingIsPushed() async {
        let store = TestStore(initialState: BrowseTabFeature.State(serverURL: serverURL)) {
            BrowseTabFeature()
        } withDependencies: {
            $0.filesClient.browse = { _, _ in BrowseResult(items: [], access: Self.readOnlyAccess, path: "") }
            $0.filesClient.favorites = { _ in [] }
        }
        // The forwarded refresh then runs the whole load cycle, covered by BrowseFeatureTests.
        store.exhaustivity = .off

        await store.send(.refreshVisibleFolder)
        await store.receive(\.root.refreshButtonTapped)
        await store.skipReceivedActions()
    }

    @Test
    func refreshVisibleFolderRefreshesTheTopPushedFolder() async {
        var state = BrowseTabFeature.State(serverURL: serverURL)
        state.path.append(BrowseFeature.State(serverURL: serverURL, directoryPath: "A", title: "A"))
        state.path.append(BrowseFeature.State(serverURL: serverURL, directoryPath: "A/B", title: "B"))
        let store = TestStore(initialState: state) {
            BrowseTabFeature()
        } withDependencies: {
            $0.filesClient.browse = { _, _ in BrowseResult(items: [], access: Self.readOnlyAccess, path: "A/B") }
            $0.filesClient.favorites = { _ in [] }
        }
        store.exhaustivity = .off

        await store.send(.refreshVisibleFolder)
        await store.receive(\.path[id: 1].refreshButtonTapped)
        await store.skipReceivedActions()
    }

    @Test
    func newFolderInVisibleFolderOpensTheSheetOnTheTopPushedFolder() async {
        var state = BrowseTabFeature.State(serverURL: serverURL)
        state.path.append(BrowseFeature.State(serverURL: serverURL, directoryPath: "A", title: "A"))
        let store = TestStore(initialState: state) {
            BrowseTabFeature()
        }

        await store.send(.newFolderInVisibleFolder)
        await store.receive(\.path[id: 0].newFolderTapped) {
            $0.path[id: 0]?.isNewFolderSheetPresented = true
        }
    }

    @Test
    func newFolderInVisibleFolderDoesNothingAtTheRoot() async {
        let store = TestStore(initialState: BrowseTabFeature.State(serverURL: serverURL)) {
            BrowseTabFeature()
        }

        await store.send(.newFolderInVisibleFolder)
    }
}
