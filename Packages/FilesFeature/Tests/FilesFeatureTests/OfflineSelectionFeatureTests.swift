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
struct OfflineSelectionFeatureTests {
    private typealias Store = TestStoreOf<OfflineSelectionFeature>

    private let serverURL = URL(fileURLWithPath: "/")

    private nonisolated func folder(_ name: String, path: String = "") -> FileItem {
        FileItem(name: name, path: path, dateModified: MockDate.date, size: 0, kind: "directory")
    }

    private nonisolated func file(_ name: String, path: String = "", size: Int64 = 100) -> FileItem {
        FileItem(name: name, path: path, dateModified: MockDate.date, size: size, kind: "txt")
    }

    private nonisolated func listing(_ items: [FileItem], path: String = "") -> BrowseResult {
        BrowseResult(
            items: items,
            access: FileAccess(canRead: true, canWrite: true, canUpload: true, canDelete: true, canShare: false, canDownload: true),
            path: path
        )
    }

    private func makeStore(
        _ state: OfflineSelectionFeature.State? = nil,
        configure: (inout DependencyValues) -> Void = { _ in }
    ) -> Store {
        TestStore(initialState: state ?? OfflineSelectionFeature.State(serverURL: serverURL)) {
            OfflineSelectionFeature()
        } withDependencies: {
            configure(&$0)
        }
    }

    @Test
    func onAppearLoadsFoldersBeforeFiles() async {
        let docs = folder("Docs")
        let note = file("a.txt")
        let result = listing([note, docs])
        let store = makeStore { $0.filesClient.browse = { _, _ in result } }

        await store.send(.onAppear) { $0.phase = .loading }
        await store.receive(\.itemsResponse.success) {
            $0.phase = .loaded
            $0.items = IdentifiedArray(uniqueElements: [docs, note])
        }
    }

    @Test
    func onAppearDoesNotReloadAScreenThatAlreadyLoaded() async {
        var state = OfflineSelectionFeature.State(serverURL: serverURL)
        state.phase = .loaded
        state.items = [file("a.txt")]
        let store = makeStore(state)

        await store.send(.onAppear)
    }

    @Test
    func selectingAFileAddsItsOwnSizeToTheEstimate() async {
        let store = makeStore()
        let target = file("a.txt", size: 250)

        await store.send(.selectionToggled(target)) {
            $0.selection[target.id] = target
        }
        #expect(store.state.estimatedBytes == 250)
        #expect(store.state.canConfirm)

        await store.send(.selectionToggled(target)) {
            $0.selection[target.id] = nil
        }
        #expect(store.state.estimatedBytes == 0)
        #expect(!store.state.canConfirm)
    }

    @Test
    func selectingAFolderFetchesItsRecursiveSizeForTheEstimate() async {
        let usagePaths = LockIsolated<[String]>([])
        let store = makeStore {
            $0.filesClient.fetchUsage = { _, path in
                usagePaths.withValue { $0.append(path) }
                return StorageUsage(path: path, size: 5000, free: 0, total: 0)
            }
        }
        let docs = folder("Docs")

        await store.send(.selectionToggled(docs)) {
            $0.selection[docs.id] = docs
            $0.estimatingPaths = ["Docs"]
        }
        #expect(store.state.isEstimating)
        await store.receive(\.usageResponse) {
            $0.estimatingPaths = []
            $0.folderSizes["Docs"] = 5000
        }
        #expect(store.state.estimatedBytes == 5000)
        #expect(usagePaths.value == ["Docs"])
    }

    @Test
    func aFolderWhoseSizeCannotBeFetchedStopsCalculatingAndCountsAsZero() async {
        let store = makeStore { $0.filesClient.fetchUsage = { _, _ in throw FilesClientError.server(statusCode: 500) } }
        let docs = folder("Docs")

        await store.send(.selectionToggled(docs)) {
            $0.selection[docs.id] = docs
            $0.estimatingPaths = ["Docs"]
        }
        await store.receive(\.usageResponse) { $0.estimatingPaths = [] }
        #expect(!store.state.isEstimating)
        #expect(store.state.estimatedBytes == 0)
    }

    @Test
    func deselectingAFolderWhileItsSizeIsPendingCancelsTheLookup() async {
        let store = makeStore {
            $0.filesClient.fetchUsage = { _, _ in
                try await suspendUntilCancelled()
                return StorageUsage(path: "Docs", size: 5000, free: 0, total: 0)
            }
        }
        let docs = folder("Docs")

        await store.send(.selectionToggled(docs)) {
            $0.selection[docs.id] = docs
            $0.estimatingPaths = ["Docs"]
        }
        await store.send(.selectionToggled(docs)) {
            $0.selection[docs.id] = nil
            $0.estimatingPaths = []
        }
        await store.finish()
        #expect(store.state.folderSizes.isEmpty)
    }

    @Test
    func anAlreadyPinnedFileCannotBeSelectedOrReQueued() async {
        var state = OfflineSelectionFeature.State(serverURL: serverURL)
        let cached = file("a.txt", size: 100)
        state.alreadyOfflineIDs = [cached.id]
        let store = makeStore(state)

        await store.send(.selectionToggled(cached))
        #expect(store.state.selection.isEmpty)
        #expect(store.state.estimatedBytes == 0)
    }

    @Test
    func loadMarksFilesAlreadyDownloadedForOffline() async {
        let cachedURL = URL(fileURLWithPath: "/tmp/a.txt")
        let first = file("a.txt")
        let second = file("b.txt")
        let result = listing([first, second])
        let store = makeStore {
            $0.filesClient.browse = { _, _ in result }
            $0.offlineFileStore = .inMemory(localURLs: ["a.txt": cachedURL])
        }

        await store.send(.onAppear) { $0.phase = .loading }
        await store.receive(\.itemsResponse.success) {
            $0.phase = .loaded
            $0.items = IdentifiedArray(uniqueElements: [first, second])
            $0.alreadyOfflineIDs = ["a.txt"]
        }
    }

    @Test
    func loadMarksPinnedFoldersAndTheirDescendantsAsDownloaded() async {
        let offline = OfflineFileStore.inMemory()
        offline.setPinnedRoots([OfflinePinnedRoot(path: "Docs", isDirectory: true)])
        let inside = folder("Sub", path: "Docs")
        let outside = folder("Other", path: "Docs2")
        let result = listing([inside, outside], path: "Docs")
        let store = makeStore {
            $0.filesClient.browse = { _, _ in result }
            $0.offlineFileStore = offline
        }

        await store.send(.onAppear) { $0.phase = .loading }
        await store.receive(\.itemsResponse.success) {
            $0.phase = .loaded
            $0.items = IdentifiedArray(uniqueElements: [outside, inside])
            $0.alreadyOfflineIDs = ["Docs/Sub"]
        }
    }

    @Test
    func loadMarksAPinnedRootFolderAsDownloaded() async {
        let offline = OfflineFileStore.inMemory()
        offline.setPinnedRoots([OfflinePinnedRoot(path: "Docs", isDirectory: true)])
        let docs = folder("Docs")
        let other = folder("Other")
        let result = listing([docs, other])
        let store = makeStore {
            $0.filesClient.browse = { _, _ in result }
            $0.offlineFileStore = offline
        }

        await store.send(.onAppear) { $0.phase = .loading }
        await store.receive(\.itemsResponse.success) {
            $0.phase = .loaded
            $0.items = IdentifiedArray(uniqueElements: [docs, other])
            $0.alreadyOfflineIDs = ["Docs"]
        }
    }

    @Test
    func openingAFolderLoadsItAndBackReturnsToTheParent() async {
        let docs = folder("Docs")
        let note = file("n.txt", path: "Docs")
        let browsed = LockIsolated<[String]>([])
        let store = makeStore {
            $0.filesClient.browse = { _, path in
                browsed.withValue { $0.append(path) }
                return listing(path == "Docs" ? [note] : [docs], path: path)
            }
        }

        await store.send(.folderTapped(docs)) {
            $0.navigationHistory = [""]
            $0.directoryPath = "Docs"
            $0.phase = .loading
        }
        await store.receive(\.itemsResponse.success) {
            $0.phase = .loaded
            $0.items = [note]
        }
        await store.send(.backTapped) {
            $0.navigationHistory = []
            $0.directoryPath = ""
            $0.phase = .loading
        }
        await store.receive(\.itemsResponse.success) {
            $0.phase = .loaded
            $0.items = [docs]
        }
        #expect(browsed.value == ["Docs", ""])
    }

    @Test
    func confirmEmitsTheSelectedRoots() async {
        var state = OfflineSelectionFeature.State(serverURL: serverURL)
        let docs = folder("Docs")
        state.selection = [docs.id: docs]
        let store = makeStore(state)

        await store.send(.confirmTapped)
        await store.receive(.delegate(.confirmed([docs])))
    }

    @Test
    func confirmWithNothingSelectedDoesNothing() async {
        let store = makeStore()

        await store.send(.confirmTapped)
    }

    @Test
    func cancelTellsTheParent() async {
        let store = makeStore()

        await store.send(.cancelTapped)
        await store.receive(.delegate(.cancelled))
    }

    @Test
    func loadFailureSurfacesAReadableError() async {
        let store = makeStore { $0.filesClient.browse = { _, _ in throw FilesClientError.server(statusCode: 500) } }

        await store.send(.onAppear) { $0.phase = .loading }
        await store.receive(\.itemsResponse.failure) {
            $0.phase = .failed(L10n.Offline.selectionLoadFailed)
        }
    }

    @Test
    func anExpiredSessionKeepsItsOwnMessage() async {
        let store = makeStore { $0.filesClient.browse = { _, _ in throw FilesClientError.sessionExpired } }

        await store.send(.onAppear) { $0.phase = .loading }
        await store.receive(\.itemsResponse.failure) {
            $0.phase = .failed(FilesClientError.sessionExpired.userMessage)
        }
    }
}
