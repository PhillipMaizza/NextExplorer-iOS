import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Localization
import Testing

@MainActor
struct OfflineSelectionFeatureTests {
    private let serverURL = URL(string: "https://example.com")!

    private nonisolated func folder(_ name: String, path: String = "") -> FileItem {
        FileItem(name: name, path: path, dateModified: Date(timeIntervalSince1970: 1), size: 0, kind: "directory")
    }

    private nonisolated func file(_ name: String, path: String = "", size: Int64 = 100) -> FileItem {
        FileItem(name: name, path: path, dateModified: Date(timeIntervalSince1970: 1), size: size, kind: "txt")
    }

    private nonisolated func access() -> FileAccess {
        FileAccess(canRead: true, canWrite: true, canUpload: true, canDelete: true, canShare: false, canDownload: true)
    }

    @Test
    func onAppearLoadsFilesAndFolders() async {
        let store = TestStore(initialState: OfflineSelectionFeature.State(serverURL: serverURL)) {
            OfflineSelectionFeature()
        } withDependencies: {
            $0.filesClient.browse = { _, _ in
                BrowseResult(items: [folder("Docs"), file("a.txt")], access: access(), path: "")
            }
        }
        store.exhaustivity = .off

        await store.send(.onAppear) { $0.phase = .loading }
        await store.receive(\.itemsResponse.success)
        #expect(store.state.phase == .loaded)
        #expect(store.state.items.count == 2)
    }

    @Test
    func selectingAFileAddsItsOwnSizeToTheEstimate() async {
        let store = TestStore(initialState: OfflineSelectionFeature.State(serverURL: serverURL)) {
            OfflineSelectionFeature()
        }
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
        let store = TestStore(initialState: OfflineSelectionFeature.State(serverURL: serverURL)) {
            OfflineSelectionFeature()
        } withDependencies: {
            $0.filesClient.fetchUsage = { _, path in StorageUsage(path: path, size: 5000, free: 0, total: 0) }
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
    }

    @Test
    func anAlreadyPinnedFileCannotBeSelectedOrReQueued() async {
        var state = OfflineSelectionFeature.State(serverURL: serverURL)
        let cached = file("a.txt", size: 100)
        state.alreadyOfflineIDs = [cached.id]

        let store = TestStore(initialState: state) { OfflineSelectionFeature() }

        await store.send(.selectionToggled(cached)) // no-op: already offline
        #expect(store.state.selection.isEmpty)
        #expect(store.state.estimatedBytes == 0)
    }

    @Test
    func loadMarksFilesAlreadyDownloadedForOffline() async {
        let cachedURL = URL(fileURLWithPath: "/tmp/a.txt")
        let store = TestStore(initialState: OfflineSelectionFeature.State(serverURL: serverURL)) {
            OfflineSelectionFeature()
        } withDependencies: {
            $0.filesClient.browse = { _, _ in
                BrowseResult(items: [file("a.txt"), file("b.txt")], access: access(), path: "")
            }
            $0.offlineFileStore = .inMemory(localURLs: ["a.txt": cachedURL])
        }
        store.exhaustivity = .off

        await store.send(.onAppear)
        await store.receive(\.itemsResponse.success)
        #expect(store.state.alreadyOfflineIDs == ["a.txt"])
    }

    @Test
    func loadMarksPinnedFoldersAsDownloaded() async {
        let offline = OfflineFileStore.inMemory()
        offline.setPinnedRoots([OfflinePinnedRoot(path: "Docs", isDirectory: true)])
        let store = TestStore(initialState: OfflineSelectionFeature.State(serverURL: serverURL)) {
            OfflineSelectionFeature()
        } withDependencies: {
            $0.filesClient.browse = { _, _ in
                BrowseResult(items: [folder("Docs"), folder("Other")], access: access(), path: "")
            }
            $0.offlineFileStore = offline
        }
        store.exhaustivity = .off

        await store.send(.onAppear)
        await store.receive(\.itemsResponse.success)
        #expect(store.state.alreadyOfflineIDs == ["Docs"])
    }

    @Test
    func confirmEmitsTheSelectedRoots() async {
        var state = OfflineSelectionFeature.State(serverURL: serverURL)
        let docs = folder("Docs")
        state.selection = [docs.id: docs]

        let store = TestStore(initialState: state) { OfflineSelectionFeature() }
        store.exhaustivity = .off

        await store.send(.confirmTapped)
        await store.receive(.delegate(.confirmed([docs])))
    }

    @Test
    func loadFailureSurfacesAReadableError() async {
        let store = TestStore(initialState: OfflineSelectionFeature.State(serverURL: serverURL)) {
            OfflineSelectionFeature()
        } withDependencies: {
            $0.filesClient.browse = { _, _ in throw FilesClientError.server(statusCode: 500) }
        }
        store.exhaustivity = .off

        await store.send(.onAppear)
        await store.receive(\.itemsResponse.failure) {
            $0.phase = .failed(L10n.Offline.selectionLoadFailed)
        }
    }
}
