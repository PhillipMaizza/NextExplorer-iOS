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
    private enum Constants {
        static let folderBytes: Int64 = 5000
        static let volumeBytes: Int64 = 16_000_000_000_000
    }

    private typealias Store = TestStoreOf<OfflineSelectionFeature>

    private let serverURL = URL(fileURLWithPath: "/")

    private nonisolated func folder(_ name: String, path: String = "") -> FileItem {
        FileItem(name: name, path: path, dateModified: MockDate.date, size: 0, kind: FileItem.directoryKind)
    }

    private nonisolated func file(_ name: String, path: String = "", size: Int64 = 100) -> FileItem {
        FileItem(name: name, path: path, dateModified: MockDate.date, size: size, kind: TestKind.text)
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
        let docs = folder(TestFolder.docs)
        let note = file(TestFile.aText)
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
        state.items = [file(TestFile.aText)]
        let store = makeStore(state)

        await store.send(.onAppear)
    }

    @Test
    func selectingAFileAddsItsOwnSizeToTheEstimate() async {
        let store = makeStore()
        let target = file(TestFile.aText, size: 250)

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
        let metadataPaths = LockIsolated<[String]>([])
        let store = makeStore {
            $0.filesClient.fetchUsage = { _, path in
                Issue.record("the estimate must not read the volume usage of \(path)")
                return StorageUsage(path: path, size: Constants.volumeBytes, free: 0, total: 0)
            }
            $0.filesClient.fetchMetadata = { _, path in
                metadataPaths.withValue { $0.append(path) }
                return Self.folderMetadata(path, totalSize: Constants.folderBytes)
            }
        }
        let docs = folder(TestFolder.docs)

        await store.send(.selectionToggled(docs)) {
            $0.selection[docs.id] = docs
            $0.estimatingPaths = [TestFolder.docs]
        }
        #expect(store.state.isEstimating)
        await store.receive(\.folderSizeResponse) {
            $0.estimatingPaths = []
            $0.folderSizes[TestFolder.docs] = 5000
        }
        #expect(store.state.estimatedBytes == 5000)
        #expect(metadataPaths.value == [TestFolder.docs])
    }

    @Test
    func aFolderWhoseSizeCannotBeFetchedStopsCalculatingAndCountsAsZero() async {
        let store = makeStore { $0.filesClient.fetchMetadata = { _, _ in throw FilesClientError.server(statusCode: 500) } }
        let docs = folder(TestFolder.docs)

        await store.send(.selectionToggled(docs)) {
            $0.selection[docs.id] = docs
            $0.estimatingPaths = [TestFolder.docs]
        }
        await store.receive(\.folderSizeResponse) { $0.estimatingPaths = [] }
        #expect(!store.state.isEstimating)
        #expect(store.state.estimatedBytes == 0)
        #expect(store.state.canConfirm)
    }

    @Test
    func deselectingAFolderWhileItsSizeIsPendingCancelsTheLookup() async {
        let store = makeStore {
            $0.filesClient.fetchMetadata = { _, path in
                try await suspendUntilCancelled()
                return Self.folderMetadata(path, totalSize: Constants.folderBytes)
            }
        }
        let docs = folder(TestFolder.docs)

        await store.send(.selectionToggled(docs)) {
            $0.selection[docs.id] = docs
            $0.estimatingPaths = [TestFolder.docs]
        }
        await store.send(.selectionToggled(docs)) {
            $0.selection[docs.id] = nil
            $0.estimatingPaths = []
        }
        await store.finish()
        #expect(store.state.folderSizes.isEmpty)
    }

    @Test
    func aSizeThatLandsAfterTheFolderWasDeselectedIsIgnored() async {
        let store = makeStore()
        let docs = folder(TestFolder.docs)

        await store.send(.folderSizeResponse(path: docs.id, .success(9000)))
        #expect(store.state.folderSizes.isEmpty)
        #expect(store.state.estimatedBytes == 0)
    }

    private nonisolated static func folderMetadata(_ path: String, totalSize: Int64) -> FileMetadata {
        FileMetadata(
            path: path, name: path, kind: FileItem.directoryKind, size: 4096,
            dateModified: MockDate.date, dateCreated: MockDate.date,
            directory: FileMetadata.DirectorySummary(totalSize: totalSize, fileCount: 3, dirCount: 1, truncated: false)
        )
    }

    @Test
    func anAlreadyPinnedFileCannotBeSelectedOrReQueued() async {
        var state = OfflineSelectionFeature.State(serverURL: serverURL)
        let cached = file(TestFile.aText, size: 100)
        state.alreadyOfflineIDs = [cached.id]
        let store = makeStore(state)

        await store.send(.selectionToggled(cached))
        #expect(store.state.selection.isEmpty)
        #expect(store.state.estimatedBytes == 0)
    }

    @Test
    func loadMarksFilesAlreadyDownloadedForOffline() async {
        let cachedURL = URL(fileURLWithPath: "/tmp/a.txt")
        let first = file(TestFile.aText)
        let second = file(TestFile.bText)
        let result = listing([first, second])
        let store = makeStore {
            $0.filesClient.browse = { _, _ in result }
            $0.offlineFileStore = .inMemory(localURLs: [TestFile.aText: cachedURL])
        }

        await store.send(.onAppear) { $0.phase = .loading }
        await store.receive(\.itemsResponse.success) {
            $0.phase = .loaded
            $0.items = IdentifiedArray(uniqueElements: [first, second])
            $0.alreadyOfflineIDs = [TestFile.aText]
        }
    }

    @Test
    func loadMarksPinnedFoldersAndTheirDescendantsAsDownloaded() async {
        let offline = OfflineFileStore.inMemory()
        offline.setPinnedRoots([OfflinePinnedRoot(path: TestFolder.docs, isDirectory: true)])
        let inside = folder("Sub", path: TestFolder.docs)
        let outside = folder("Other", path: "Docs2")
        let result = listing([inside, outside], path: TestFolder.docs)
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
        offline.setPinnedRoots([OfflinePinnedRoot(path: TestFolder.docs, isDirectory: true)])
        let docs = folder(TestFolder.docs)
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
            $0.alreadyOfflineIDs = [TestFolder.docs]
        }
    }

    @Test
    func openingAFolderLoadsItAndBackReturnsToTheParent() async {
        let docs = folder(TestFolder.docs)
        let note = file("n.txt", path: TestFolder.docs)
        let browsed = LockIsolated<[String]>([])
        let store = makeStore {
            $0.filesClient.browse = { _, path in
                browsed.withValue { $0.append(path) }
                return listing(path == TestFolder.docs ? [note] : [docs], path: path)
            }
        }

        await store.send(.folderTapped(docs)) {
            $0.navigationHistory = [""]
            $0.directoryPath = TestFolder.docs
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
        #expect(browsed.value == [TestFolder.docs, ""])
    }

    @Test
    func confirmEmitsTheSelectedRoots() async {
        var state = OfflineSelectionFeature.State(serverURL: serverURL)
        let docs = folder(TestFolder.docs)
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
