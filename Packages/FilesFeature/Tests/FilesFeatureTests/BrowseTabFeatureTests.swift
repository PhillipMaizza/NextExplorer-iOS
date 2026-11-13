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
struct BrowseTabFeatureTests {
    private let serverURL = BrowseTestSupport.serverURL
    private let readOnlyAccess = BrowseTestSupport.readOnlyAccess

    private func screen(_ path: String, title: String? = nil) -> BrowseFeature.State {
        BrowseFeature.State(
            serverURL: serverURL,
            directoryPath: path,
            title: title ?? (path as NSString).lastPathComponent
        )
    }

    private func makeState(pushing paths: [String] = []) -> BrowseTabFeature.State {
        var state = BrowseTabFeature.State(serverURL: serverURL)
        for path in paths {
            state.path.append(screen(path))
        }
        return state
    }

    private func makeStore(
        _ state: BrowseTabFeature.State? = nil,
        configure: (inout DependencyValues) -> Void = { _ in }
    ) -> TestStoreOf<BrowseTabFeature> {
        TestStore(initialState: state ?? makeState()) {
            BrowseTabFeature()
        } withDependencies: {
            $0.date = .constant(MockDate.date)
            configure(&$0)
        }
    }

    /// The load of a screen that answers with an empty listing: it asks for the folder, then for favorites.
    private func finishRootLoad(_ store: TestStoreOf<BrowseTabFeature>, listing: AsyncGate) async {
        listing.open()
        await store.receive(\.root.itemsResponse.success) {
            $0.root.phase = .loaded
            $0.root.access = readOnlyAccess
        }
        await store.receive(\.root.favoritesResponse) {
            $0.root.hasLoadedFavorites = true
        }
    }

    private func finishPathLoad(_ store: TestStoreOf<BrowseTabFeature>, id: StackElementID, listing: AsyncGate) async {
        listing.open()
        await store.receive(\.path[id: id].itemsResponse.success) {
            $0.path[id: id]?.phase = .loaded
            $0.path[id: id]?.access = readOnlyAccess
        }
        await store.receive(\.path[id: id].favoritesResponse) {
            $0.path[id: id]?.hasLoadedFavorites = true
        }
    }

    // MARK: Navigation

    @Test("Opening a folder from the root pushes it onto the path stack")
    func openingAFolderFromTheRootPushesItOntoThePathStack() async {
        let item = FileItem(
            name: TestFolder.photos,
            path: "",
            dateModified: MockDate.date,
            size: 0,
            kind: FileItem.directoryKind
        )
        let store = makeStore()

        await store.send(.root(.delegate(.openFolder(item)))) {
            $0.path.append(screen(TestFolder.photos))
        }
    }

    @Test("Opening a folder from a pushed screen pushes another level")
    func openingAFolderFromAPushedScreenPushesAnotherLevel() async {
        let nested = FileItem(
            name: "Vacation",
            path: TestFolder.photos,
            dateModified: MockDate.date,
            size: 0,
            kind: FileItem.directoryKind
        )
        let state = makeState(pushing: [TestFolder.photos])
        let store = makeStore(state)

        await store.send(.path(.element(id: state.path.ids[0], action: .delegate(.openFolder(nested))))) {
            $0.path.append(screen("Photos/Vacation"))
        }
    }

    @Test("Opening a folder drops what Forward would have reopened")
    func openingAFolderClearsTheForwardStack() async {
        var state = makeState()
        state.forwardStack = [screen("Old")]
        let item = FileItem(
            name: TestFolder.photos,
            path: "",
            dateModified: MockDate.date,
            size: 0,
            kind: FileItem.directoryKind
        )
        let store = makeStore(state)

        await store.send(.root(.delegate(.openFolder(item)))) {
            $0.forwardStack = []
            $0.path.append(screen(TestFolder.photos))
        }
    }

    @Test("Navigating to a path replaces the entire stack with that folder, also when it is already open")
    func navigatingToANonEmptyPathReplacesTheEntirePathStack() async {
        let store = makeStore(makeState(pushing: ["A", "A/B"]))

        await store.send(.navigateToDirectory(path: TestFolder.photos, title: TestFolder.photos)) {
            $0.path = StackState([screen(TestFolder.photos)])
        }
        await store.send(.navigateToDirectory(path: TestFolder.photos, title: TestFolder.photos)) {
            $0.path = StackState([screen(TestFolder.photos)])
        }
    }

    @Test("Navigating to the empty path clears the stack and stays on the root")
    func navigatingToAnEmptyPathClearsTheStackAndStaysOnRoot() async {
        let store = makeStore(makeState(pushing: ["A"]))

        await store.send(.navigateToDirectory(path: "", title: "Home")) {
            $0.path = StackState()
        }
    }

    @Test("An open path request from the root is forwarded to navigateToDirectory")
    func openPathDelegateFromTheRootForwardsToNavigateToDirectory() async {
        let store = makeStore()

        await store.send(.root(.delegate(.openPath(path: TestFolder.photos, title: TestFolder.photos))))
        await store.receive(\.navigateToDirectory) {
            $0.path[id: 0] = screen(TestFolder.photos)
        }
    }

    @Test("An open path request from a pushed screen is forwarded to navigateToDirectory")
    func openPathDelegateFromAPushedScreenForwardsToNavigateToDirectory() async {
        let state = makeState(pushing: ["A"])
        let store = makeStore(state)

        await store.send(.path(.element(id: state.path.ids[0], action: .delegate(.openPath(path: "", title: "Home")))))
        await store.receive(.navigateToDirectory(path: "", title: "Home")) {
            $0.path = StackState()
        }
    }

    // MARK: Delegates bubbling up

    struct Bubble: Sendable, CustomTestStringConvertible {
        let fromScreen: BrowseFeature.Action.Delegate
        let upward: BrowseTabFeature.Action.Delegate

        var testDescription: String {
            "\(upward)"
        }
    }

    private nonisolated static let upload = PendingUpload(
        id: UUID(0),
        fileURL: URL(fileURLWithPath: "/tmp/a.txt"),
        fileName: TestFile.aText,
        destination: TestFolder.docs
    )
    private nonisolated static let item = FileItem(
        name: TestFile.aText,
        path: TestFolder.docs,
        dateModified: MockDate.date,
        size: 1,
        kind: TestKind.text
    )
    private nonisolated static let saveRequest = DownloadSaveRequest(
        item: item,
        target: .into(URL(fileURLWithPath: "/tmp"))
    )

    @Test(
        "What a screen asks of the app shell bubbles up, from the root and from a pushed screen alike",
        arguments: [
            Bubble(fromScreen: .favoritesChanged, upward: .favoritesChanged),
            Bubble(fromScreen: .openDownloadsTapped, upward: .openDownloadsTapped),
            Bubble(fromScreen: .goToSharedTab, upward: .goToSharedTab),
            Bubble(fromScreen: .uploadRequested([upload]), upward: .uploadRequested([upload])),
            Bubble(fromScreen: .downloadRequested([item]), upward: .downloadRequested([item])),
            Bubble(fromScreen: .saveRequested([saveRequest]), upward: .saveRequested([saveRequest])),
        ]
    )
    func delegatesBubbleUp(_ bubble: Bubble) async {
        let state = makeState(pushing: [TestFolder.photos])
        let store = makeStore(state)

        await store.send(.root(.delegate(bubble.fromScreen)))
        await store.receive(.delegate(bubble.upward))
        await store.send(.path(.element(id: state.path.ids[0], action: .delegate(bubble.fromScreen))))
        await store.receive(.delegate(bubble.upward))
    }

    // MARK: Pasting

    @Test("Pasting a folder into its own folder shows the copy at once, and the refresh that follows confirms it")
    func pastingAFolderIntoItsOwnFolderShowsTheCopyWithoutARefresh() async throws {
        let now = MockDate.date.addingTimeInterval(100)
        let misc = FileItem(
            name: "Misc",
            path: TestFolder.docs,
            dateModified: MockDate.date,
            size: 0,
            kind: FileItem.directoryKind
        )
        let copy = FileItem(
            name: "Misc (2)",
            path: TestFolder.docs,
            dateModified: now,
            size: 0,
            kind: FileItem.directoryKind
        )
        let full = BrowseTestSupport.fullAccess
        var docs = screen(TestFolder.docs)
        docs.items = [misc]
        docs.phase = .loaded
        docs.access = full
        docs.$clipboard.withLock { $0 = FileClipboard(items: [misc], operation: .copy) }
        var state = makeState()
        state.path.append(docs)
        let id = state.path.ids[0]

        let transfer = AsyncGate()
        let rootListing = AsyncGate()
        let docsListing = AsyncGate()
        let favoritesCalls = NumberedCalls(capacity: 2)
        let transferred = LockIsolated<[String]>([])
        let store = makeStore(state) {
            $0.date = .constant(now)
            $0.filesClient.transferItems = { _, items, destination, operation in
                transferred
                    .withValue { $0.append("\(items.map(\.id).joined(separator: ",")) \(destination) \(operation)") }
                try await transfer.wait()
                return TransferResult(destination: destination, items: [.init(from: "Docs/Misc", to: "Docs/Misc (2)")])
            }
            $0.filesClient.browse = { _, path in
                if path == TestFolder.docs {
                    try await docsListing.wait()
                    return BrowseResult(items: [misc, copy], access: full, path: path)
                }
                try await rootListing.wait()
                return BrowseResult(items: [], access: BrowseTestSupport.readOnlyAccess, path: path)
            }
            $0.filesClient.favorites = { _ in
                try await favoritesCalls.park()
                return []
            }
            $0.filesClient.serverFeatures = { _ in throw FilesClientError.offline }
        }

        await store.send(.path(.element(id: id, action: .pasteTapped(keepItemsAfterCopy: false)))) {
            $0.path[id: id]?.isPerformingFileAction = true
            $0.path[id: id]?.fileActionProgressMessage = L10n.Browse.progressCopying
            $0.path[id: id]?.pendingTransferRetry = BrowseFeature.TransferRetry(
                items: [misc], destination: TestFolder.docs, operation: .copy, clearClipboard: true,
                resolution: .keepBoth, itemsToReplace: []
            )
        }
        transfer.open()
        await store.receive(\.path[id: id].transferResponse.success) {
            $0.path[id: id]?.isPerformingFileAction = false
            $0.path[id: id]?.fileActionProgressMessage = nil
            $0.path[id: id]?.pendingTransferRetry = nil
            $0.path[id: id]?.$clipboard.withLock { $0 = nil }
            $0.path[id: id]?.transferSuccessMessage = L10n.Browse.transferCopied(1)
            $0.path[id: id]?.items = [misc, copy]
            $0.path[id: id]?.$undoStack.withLock { $0 = [FileUndoEntry(.created([copy]))] }
            $0.path[id: id]?.awaitedArrivalIDs = ["Docs/Misc (2)"]
            $0.path[id: id]?.arrivalChecksLeft = 3
        }
        await store.receive(.path(.element(id: id, action: .delegate(.directoryContentsChanged))))
        await store.receive(\.syncPathStack)
        await store.receive(\.root.refreshButtonTapped) {
            $0.root.phase = .loading
        }
        await store.receive(\.path[id: id].refreshButtonTapped) {
            $0.path[id: id]?.phase = .loading
        }
        rootListing.open()
        await store.receive(\.root.itemsResponse.success) {
            $0.root.phase = .loaded
            $0.root.access = readOnlyAccess
        }
        try await favoritesCalls.arrival(0)
        favoritesCalls.release(0)
        await store.receive(\.root.favoritesResponse) {
            $0.root.hasLoadedFavorites = true
        }
        docsListing.open()
        await store.receive(\.path[id: id].itemsResponse.success) {
            $0.path[id: id]?.phase = .loaded
            $0.path[id: id]?.awaitedArrivalIDs = []
            $0.path[id: id]?.arrivalChecksLeft = 0
        }
        await store.receive(\.path[id: id].offlineAvailabilityComputed)
        try await favoritesCalls.arrival(1)
        favoritesCalls.release(1)
        await store.receive(\.path[id: id].favoritesResponse) {
            $0.path[id: id]?.hasLoadedFavorites = true
        }

        #expect(transferred.value == ["Docs/Misc Docs copy"])
    }

    // MARK: Sync on app open

    @Test("Syncing refreshes only the root when no folder is pushed")
    func syncPathStackRefreshesOnlyTheRootWhenNoFolderIsPushed() async {
        let listing = AsyncGate()
        let store = makeStore { $0.holdFolderListings(["": listing]) }

        await store.send(.syncPathStack)
        await store.receive(\.root.refreshButtonTapped) {
            $0.root.phase = .loading
        }
        await finishRootLoad(store, listing: listing)
    }

    @Test("Syncing refreshes the root and every pushed subfolder")
    func syncPathStackRefreshesTheRootAndEveryPushedSubfolder() async {
        let state = makeState(pushing: [TestFolder.photos, "Photos/Old"])
        let ids = state.path.ids
        let gates = ["": AsyncGate(), TestFolder.photos: AsyncGate(), "Photos/Old": AsyncGate()]
        let store = makeStore(state) { $0.holdFolderListings(gates) }

        await store.send(.syncPathStack)
        await store.receive(\.root.refreshButtonTapped) {
            $0.root.phase = .loading
        }
        await store.receive(\.path[id: ids[0]].refreshButtonTapped) {
            $0.path[id: ids[0]]?.phase = .loading
        }
        await store.receive(\.path[id: ids[1]].refreshButtonTapped) {
            $0.path[id: ids[1]]?.phase = .loading
        }
        await finishRootLoad(store, listing: gates[""] ?? AsyncGate())
        await finishPathLoad(store, id: ids[0], listing: gates[TestFolder.photos] ?? AsyncGate())
        await finishPathLoad(store, id: ids[1], listing: gates["Photos/Old"] ?? AsyncGate())
    }

    @Test("A change reported by a pushed screen resyncs the whole stack")
    func directoryContentsChangedFromAPushedScreenReSyncsTheWholeStack() async {
        let state = makeState(pushing: [TestFolder.photos])
        let id = state.path.ids[0]
        let gates = ["": AsyncGate(), TestFolder.photos: AsyncGate()]
        let store = makeStore(state) { $0.holdFolderListings(gates) }

        await store.send(.path(.element(id: id, action: .delegate(.directoryContentsChanged))))
        await store.receive(\.syncPathStack)
        await store.receive(\.root.refreshButtonTapped) {
            $0.root.phase = .loading
        }
        await store.receive(\.path[id: id].refreshButtonTapped) {
            $0.path[id: id]?.phase = .loading
        }
        await finishRootLoad(store, listing: gates[""] ?? AsyncGate())
        await finishPathLoad(store, id: id, listing: gates[TestFolder.photos] ?? AsyncGate())
    }

    @Test("A change reported by the root resyncs the whole stack")
    func directoryContentsChangedFromTheRootReSyncsTheWholeStack() async {
        let state = makeState(pushing: [TestFolder.photos])
        let id = state.path.ids[0]
        let gates = ["": AsyncGate(), TestFolder.photos: AsyncGate()]
        let store = makeStore(state) { $0.holdFolderListings(gates) }

        await store.send(.root(.delegate(.directoryContentsChanged)))
        await store.receive(\.syncPathStack)
        await store.receive(\.root.refreshButtonTapped) {
            $0.root.phase = .loading
        }
        await store.receive(\.path[id: id].refreshButtonTapped) {
            $0.path[id: id]?.phase = .loading
        }
        await finishRootLoad(store, listing: gates[""] ?? AsyncGate())
        await finishPathLoad(store, id: id, listing: gates[TestFolder.photos] ?? AsyncGate())
    }

    @Test("Refreshing one path reloads only the screen showing it, and the empty path is the root")
    func refreshDirectoryReloadsOnlyTheScreensShowingThatPath() async {
        let state = makeState(pushing: [TestFolder.photos, TestFolder.docs])
        let ids = state.path.ids
        let gates = ["": AsyncGate(), TestFolder.photos: AsyncGate()]
        let store = makeStore(state) { $0.holdFolderListings(gates) }

        await store.send(.refreshDirectory(path: TestFolder.photos))
        await store.receive(\.path[id: ids[0]].refreshButtonTapped) {
            $0.path[id: ids[0]]?.phase = .loading
        }
        await finishPathLoad(store, id: ids[0], listing: gates[TestFolder.photos] ?? AsyncGate())
        await store.send(.refreshDirectory(path: ""))
        await store.receive(\.root.refreshButtonTapped) {
            $0.root.phase = .loading
        }
        await finishRootLoad(store, listing: gates[""] ?? AsyncGate())
        await store.send(.refreshDirectory(path: "Nowhere"))
    }

    // MARK: Menu bar commands

    @Test("Refresh reloads the root when nothing is pushed")
    func refreshVisibleFolderRefreshesTheRootWhenNothingIsPushed() async {
        let listing = AsyncGate()
        let store = makeStore { $0.holdFolderListings(["": listing]) }

        await store.send(.refreshVisibleFolder)
        await store.receive(\.root.refreshButtonTapped) {
            $0.root.phase = .loading
        }
        await finishRootLoad(store, listing: listing)
    }

    @Test("Refresh reloads the top pushed folder and leaves the folders under it alone")
    func refreshVisibleFolderRefreshesTheTopPushedFolder() async {
        let state = makeState(pushing: ["A", "A/B"])
        let id = state.path.ids[1]
        let listing = AsyncGate()
        let store = makeStore(state) { $0.holdFolderListings(["A/B": listing]) }

        await store.send(.refreshVisibleFolder)
        await store.receive(\.path[id: id].refreshButtonTapped) {
            $0.path[id: id]?.phase = .loading
        }
        await finishPathLoad(store, id: id, listing: listing)
    }

    @Test("New Folder opens the sheet on the top pushed folder")
    func newFolderInVisibleFolderOpensTheSheetOnTheTopPushedFolder() async {
        let state = makeState(pushing: ["A"])
        let id = state.path.ids[0]
        let store = makeStore(state)

        await store.send(.newFolderInVisibleFolder)
        await store.receive(\.path[id: id].newFolderTapped) {
            $0.path[id: id]?.isNewFolderSheetPresented = true
        }
    }

    @Test("New Folder does nothing at the root, which is not a writable folder")
    func newFolderInVisibleFolderDoesNothingAtTheRoot() async {
        let store = makeStore()

        await store.send(.newFolderInVisibleFolder)
    }

    @Test("New File does nothing at the root, which is not a writable folder")
    func newFileInVisibleFolderDoesNothingAtTheRoot() async {
        let store = makeStore()

        await store.send(.newFileInVisibleFolder)
    }

    @Test("New File opens the sheet on the top pushed folder and asks the server for its editor extensions")
    func newFileInVisibleFolderOpensTheSheetOnTheTopPushedFolder() async {
        let state = makeState(pushing: ["A"])
        let id = state.path.ids[0]
        let store = makeStore(state) { $0.filesClient.serverFeatures = { _ in throw FilesClientError.offline } }

        await store.send(.newFileInVisibleFolder)
        await store.receive(\.path[id: id].newFileTapped) {
            $0.path[id: id]?.isNewFileSheetPresented = true
        }
        await store.finish()
    }
}
