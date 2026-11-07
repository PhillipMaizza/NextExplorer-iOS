import ComposableArchitecture
import CoreModels
import DependenciesTestSupport
import FilesClient
@testable import FilesFeature
import Foundation
import Localization
import NetworkClient
import Testing

@Suite(.dependencies)
@MainActor
struct BrowseQAFixesTests {
    private let serverURL = URL(string: "https://example.com") ?? URL(fileURLWithPath: "/")
    private let fixedDate = Date(timeIntervalSince1970: 1_000)

    private nonisolated static let access = FileAccess(
        canRead: true, canWrite: true, canUpload: true, canDelete: true, canShare: true, canDownload: true
    )

    private nonisolated func folder(_ name: String, path: String = "docs") -> FileItem {
        FileItem(name: name, path: path, dateModified: Date(timeIntervalSince1970: 0), size: 0, kind: "directory")
    }

    private nonisolated func file(_ name: String, path: String = "docs") -> FileItem {
        FileItem(name: name, path: path, dateModified: Date(timeIntervalSince1970: 0), size: 1, kind: "txt")
    }

    private nonisolated func favorite(_ path: String) -> Favorite {
        Favorite(id: path, path: path, label: nil, icon: "folder", color: nil, position: 0, createdAt: Date(timeIntervalSince1970: 0), updatedAt: Date(timeIntervalSince1970: 0))
    }

    private func loadedState(items: [FileItem], path: String = "docs") -> BrowseFeature.State {
        var state = BrowseFeature.State(serverURL: serverURL, directoryPath: path, title: "Docs")
        state.items = IdentifiedArray(uniqueElements: items)
        state.access = Self.access
        state.phase = .loaded
        state.hasLoadedFavorites = true
        return state
    }

    // MARK: Failed favorites fetch

    @Test
    func aFailedFavoritesFetchKeepsThePreviousStarsOn() async {
        var state = loadedState(items: [folder("A")])
        state.phase = .idle
        state.favoritePaths = ["docs/A"]
        let store = TestStore(initialState: state) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.browse = { _, path in BrowseResult(items: [folder("A")], access: Self.access, path: path) }
            $0.filesClient.favorites = { _ in throw FilesClientError.server(statusCode: 500) }
            $0.filesClient.prefetchDirectory = { _, _ in }
            $0.directoryCacheStore.lastWrittenAt = { _, _ in nil }
        }
        store.exhaustivity = .off

        await store.send(.onAppear)
        await store.finish()

        #expect(store.state.favoritePaths == ["docs/A"])
    }

    @Test
    func togglingAfterAFailedFavoritesFetchRemovesInsteadOfAdds() async {
        var state = loadedState(items: [folder("A")])
        state.phase = .idle
        state.favoritePaths = ["docs/A"]
        let added = LockIsolated<[String]>([])
        let removed = LockIsolated<[String]>([])
        let store = TestStore(initialState: state) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.browse = { _, path in BrowseResult(items: [folder("A")], access: Self.access, path: path) }
            $0.filesClient.favorites = { _ in throw FilesClientError.offline }
            $0.filesClient.prefetchDirectory = { _, _ in }
            $0.directoryCacheStore.lastWrittenAt = { _, _ in nil }
            $0.filesClient.addFavorite = { _, path in
                added.withValue { $0.append(path) }
                return favorite(path)
            }
            $0.filesClient.removeFavorite = { _, path in removed.withValue { $0.append(path) } }
        }
        store.exhaustivity = .off

        await store.send(.onAppear)
        await store.finish()
        await store.send(.favoriteToggleButtonTapped(folder("A")))
        await store.receive(\.favoriteToggleResponse.success)

        #expect(removed.value == ["docs/A"])
        #expect(added.value.isEmpty)
        #expect(store.state.favoritePaths.isEmpty)
    }

    // MARK: Failed refresh on a populated folder

    @Test
    func aFailedRefreshKeepsTheListAndShowsAToast() async {
        let items = [file("a.txt"), file("b.txt")]
        let store = TestStore(initialState: loadedState(items: items)) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.browse = { _, _ in throw FilesClientError.server(statusCode: 500) }
            $0.filesClient.favorites = { _ in [] }
        }
        store.exhaustivity = .off

        await store.send(.refreshButtonTapped)
        await store.receive(\.itemsResponse.failure)
        await store.finish()

        #expect(store.state.phase == .loaded)
        #expect(store.state.items.count == 2)
        #expect(store.state.fileActionErrorMessage == FilesClientError.server(statusCode: 500).userMessage)
    }

    @Test
    func aFailedLoadOfAnEmptyFolderStillShowsTheFullScreenError() async {
        var state = BrowseFeature.State(serverURL: serverURL, directoryPath: "docs", title: "Docs")
        state.phase = .idle
        let store = TestStore(initialState: state) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.browse = { _, _ in throw FilesClientError.server(statusCode: 500) }
            $0.filesClient.favorites = { _ in [] }
            $0.directoryCacheStore.read = { _, _ in nil }
        }
        store.exhaustivity = .off

        await store.send(.onAppear)
        await store.receive(\.itemsResponse.failure)
        await store.finish()

        #expect(store.state.phase == .failed(FilesClientError.server(statusCode: 500).userMessage))
        #expect(store.state.fileActionErrorMessage == nil)
    }

    // MARK: Prefetch cap

    private func prefetchRun(
        directories: [FileItem], favoritePaths: Set<String> = [], pinned: [String] = [], isMetered: Bool = false
    ) async -> [String] {
        let prefetched = LockIsolated<[String]>([])
        var state = BrowseFeature.State(serverURL: serverURL, directoryPath: "docs", title: "Docs")
        state.favoritePaths = favoritePaths
        let offline = OfflineFileStore.inMemory()
        offline.setPinnedRoots(pinned.map { OfflinePinnedRoot(path: $0, isDirectory: true) })
        let store = TestStore(initialState: state) {
            BrowseFeature()
        } withDependencies: {
            $0.connectivity = ConnectivityClient(isOnline: { true }, events: { AsyncStream { _ in } }, isMetered: { isMetered })
            $0.offlineFileStore = offline
            $0.filesClient.prefetchDirectory = { _, path in prefetched.withValue { $0.append(path) } }
            $0.directoryCacheStore.lastWrittenAt = { _, _ in nil }
        }
        store.exhaustivity = .off

        await store.send(.itemsResponse(.success(BrowseResult(items: directories, access: Self.access, path: "docs"))))
        await store.finish()
        return prefetched.value
    }

    private func manyFolders(_ count: Int) -> [FileItem] {
        (0 ..< count).map { folder(String(format: "F%02d", $0)) }
    }

    @Test
    func prefetchIsCappedAndTakesTheNearestFoldersFirst() async {
        let prefetched = await prefetchRun(directories: manyFolders(35))

        #expect(prefetched.count == BrowseFeature.Constants.maxPrefetchedFolders)
        #expect(Set(prefetched) == Set((0 ..< BrowseFeature.Constants.maxPrefetchedFolders).map { String(format: "docs/F%02d", $0) }))
    }

    @Test
    func prefetchPrefersFavoritedAndPinnedFoldersOverTheCap() async {
        let prefetched = await prefetchRun(
            directories: manyFolders(35), favoritePaths: ["docs/F33"], pinned: ["docs/F34"]
        )

        #expect(prefetched.count == BrowseFeature.Constants.maxPrefetchedFolders)
        #expect(prefetched.contains("docs/F33"))
        #expect(prefetched.contains("docs/F34"))
        #expect(!prefetched.contains("docs/F19"))
    }

    @Test
    func prefetchOrderKeepsListingOrderWithinEachGroup() {
        let order = BrowseFeature.prefetchOrder(["a", "b", "c", "d"], preferred: ["d", "b"])
        #expect(order == ["b", "d", "a", "c"])
    }

    @Test
    func prefetchIsSkippedOnAMeteredConnection() async {
        let prefetched = await prefetchRun(directories: manyFolders(5), isMetered: true)
        #expect(prefetched.isEmpty)
    }

    // MARK: Bulk favorites

    @Test
    func aPartialBulkFavoriteFailureReportsHowManyFailed() async {
        let folders = [folder("A"), folder("B"), folder("C")]
        var state = loadedState(items: folders)
        state.isSelecting = true
        state.selectedItemIDs = Set(folders.map(\.id))
        let store = TestStore(initialState: state) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.addFavorite = { _, path in
                if path == "docs/B" {
                    throw FilesClientError.server(statusCode: 500)
                }
                return favorite(path)
            }
        }
        store.exhaustivity = .off

        await store.send(.bulkFavoriteTapped)
        await store.receive(\.bulkFavoriteResponse)

        #expect(store.state.favoritePaths == ["docs/A", "docs/C"])
        #expect(store.state.fileActionErrorMessage == L10n.Browse.bulkFavoriteFailed(1, 3))
    }

    @Test
    func aFullyFailedBulkFavoriteChangesNothingAndReportsAll() async {
        let folders = [folder("A"), folder("B")]
        var state = loadedState(items: folders)
        state.selectedItemIDs = Set(folders.map(\.id))
        let store = TestStore(initialState: state) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.addFavorite = { _, _ in throw FilesClientError.offline }
        }
        store.exhaustivity = .off

        await store.send(.bulkFavoriteTapped)
        await store.receive(\.bulkFavoriteResponse)

        #expect(store.state.favoritePaths.isEmpty)
        #expect(store.state.fileActionErrorMessage == L10n.Browse.bulkFavoriteFailed(2, 2))
    }

    @Test
    func aFullySuccessfulBulkFavoriteShowsNoError() async {
        let folders = [folder("A"), folder("B")]
        var state = loadedState(items: folders)
        state.selectedItemIDs = Set(folders.map(\.id))
        let store = TestStore(initialState: state) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.addFavorite = { _, path in favorite(path) }
        }
        store.exhaustivity = .off

        await store.send(.bulkFavoriteTapped)
        await store.receive(\.bulkFavoriteResponse)

        #expect(store.state.fileActionErrorMessage == nil)
    }

    // MARK: Text save overlap

    private func editingState() -> BrowseFeature.State {
        var state = loadedState(items: [file("notes.txt")])
        state.previewItem = file("notes.txt")
        state.textContent = "old"
        state.textPhase = .loaded
        return state
    }

    @Test
    func aSaveFinishingAfterThePreviewClosedNeverWritesTheEditorContent() async {
        let gate = AsyncStream<Void>.makeStream()
        let store = TestStore(initialState: editingState()) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.saveTextContent = { _, _, _ in
                for await _ in gate.stream {
                    break
                }
            }
        }
        store.exhaustivity = .off

        await store.send(.textSaveTapped("new"))
        #expect(store.state.isSavingTextContent)

        await store.send(.previewDismissed)
        #expect(store.state.textContent == nil)
        #expect(!store.state.savingTexts.isEmpty)

        gate.continuation.yield(())
        await store.receive(\.textSaveResponse)

        #expect(store.state.savingTexts.isEmpty)
        #expect(store.state.textContent == nil)
    }

    @Test
    func aSaveFailingAfterThePreviewClosedIsReportedAsAToast() async {
        let gate = AsyncStream<Void>.makeStream()
        let store = TestStore(initialState: editingState()) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.saveTextContent = { _, _, _ in
                for await _ in gate.stream {
                    break
                }
                throw FilesClientError.server(statusCode: 500)
            }
        }
        store.exhaustivity = .off

        await store.send(.textSaveTapped("new"))
        await store.send(.previewDismissed)
        gate.continuation.yield(())
        await store.receive(\.textSaveResponse)

        #expect(store.state.savingTexts.isEmpty)
        #expect(store.state.textSaveError == nil)
        #expect(store.state.fileActionErrorMessage == FilesClientError.server(statusCode: 500).userMessage)
    }

    @Test
    func aSecondSaveIsIgnoredWhileTheFirstIsStillInFlightEvenAfterDismiss() async {
        let gate = AsyncStream<Void>.makeStream()
        let saves = LockIsolated(0)
        let store = TestStore(initialState: editingState()) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.saveTextContent = { _, _, _ in
                saves.withValue { $0 += 1 }
                for await _ in gate.stream {
                    break
                }
            }
        }
        store.exhaustivity = .off

        await store.send(.textSaveTapped("one"))
        await store.send(.previewDismissed)
        await store.send(.textSaveTapped("two"))
        gate.continuation.yield(())
        await store.receive(\.textSaveResponse)

        #expect(saves.value == 1)
    }

    @Test
    func aSecondFileCanBeSavedWhileTheFirstSaveIsStillAnswering() async {
        let gate = AsyncStream<Void>.makeStream()
        let saved = LockIsolated<[String]>([])
        let store = TestStore(initialState: editingState()) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.saveTextContent = { _, path, _ in
                saved.withValue { $0.append(path) }
                if path == "docs/notes.txt" {
                    for await _ in gate.stream {
                        break
                    }
                }
            }
            $0.filesClient.fetchTextContent = { _, _ in "other" }
        }
        store.exhaustivity = .off

        await store.send(.textSaveTapped("one"))
        await store.send(.previewDismissed)
        await store.send(.rowTapped(file("other.txt")))
        await store.send(.textSaveTapped("two"))
        #expect(store.state.savingTexts.count == 2)
        #expect(store.state.isSavingTextContent)
        await store.receive(\.textSaveResponse)

        gate.continuation.yield(())
        await store.receive(\.textSaveResponse)

        #expect(Set(saved.value) == ["docs/notes.txt", "docs/other.txt"])
        #expect(store.state.savingTexts.isEmpty)
    }

    @Test
    func openingAnotherFileNeverCancelsTheSaveOfTheFirst() async {
        let gate = AsyncStream<Void>.makeStream()
        let finished = LockIsolated(false)
        let store = TestStore(initialState: editingState()) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.saveTextContent = { _, _, _ in
                for await _ in gate.stream {
                    break
                }
                finished.setValue(true)
            }
            $0.filesClient.fetchTextContent = { _, _ in "other" }
        }
        store.exhaustivity = .off

        await store.send(.textSaveTapped("one"))
        await store.send(.rowTapped(file("other.txt")))
        gate.continuation.yield(())
        await store.receive(\.textSaveResponse)

        #expect(finished.value)
        #expect(store.state.savingTexts.isEmpty)
    }

    // MARK: Editor conflicts

    @Test
    func aFileChangedOnTheServerPromptsInsteadOfSaving() async {
        let store = TestStore(initialState: editingState()) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.saveTextContent = { _, _, _ in throw FilesClientError.changedOnServer }
        }
        store.exhaustivity = .off

        await store.send(.textSaveTapped("mine"))
        await store.receive(\.textSaveResponse)

        #expect(store.state.isTextSaveConflictPresented)
        #expect(store.state.textSaveConflict?.pendingText == "mine")
        #expect(store.state.textContent == "old")
        #expect(store.state.textSaveError == FilesClientError.changedOnServer.userMessage)
    }

    @Test
    func overwriteResendsTheEditedTextAndClearsTheConflict() async {
        let attempts = LockIsolated(0)
        let sent = LockIsolated<[String]>([])
        let store = TestStore(initialState: editingState()) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.saveTextContent = { _, _, content in
                sent.withValue { $0.append(content) }
                let attempt = attempts.withValue { value -> Int in
                    value += 1
                    return value
                }
                if attempt == 1 {
                    throw FilesClientError.changedOnServer
                }
            }
        }
        store.exhaustivity = .off

        await store.send(.textSaveTapped("mine"))
        await store.receive(\.textSaveResponse)
        await store.send(.textSaveOverwriteTapped)
        await store.receive(\.textSaveResponse)

        #expect(sent.value == ["mine", "mine"])
        #expect(store.state.isTextSaveConflictPresented == false)
        #expect(store.state.textSaveConflict == nil)
        #expect(store.state.textSaveError == nil)
        #expect(store.state.textContent == "mine")
    }

    @Test
    func cancellingTheConflictPromptAsksAgainOnTheNextSaveWithoutTouchingTheServer() async {
        let attempts = LockIsolated(0)
        let store = TestStore(initialState: editingState()) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.saveTextContent = { _, _, _ in
                attempts.withValue { $0 += 1 }
                throw FilesClientError.changedOnServer
            }
        }
        store.exhaustivity = .off

        await store.send(.textSaveTapped("mine"))
        await store.receive(\.textSaveResponse)
        await store.send(.textSaveConflictDismissed)
        #expect(store.state.isTextSaveConflictPresented == false)
        #expect(store.state.textSaveConflict?.pendingText == "mine")
        #expect(store.state.textSaveError == nil)

        await store.send(.textSaveTapped("mine again"))
        #expect(store.state.isTextSaveConflictPresented)
        #expect(store.state.textSaveConflict?.pendingText == "mine again")
        #expect(attempts.value == 1)
    }

    @Test
    func reloadFetchesTheServerCopyAndDropsTheConflict() async {
        let store = TestStore(initialState: editingState()) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.saveTextContent = { _, _, _ in throw FilesClientError.changedOnServer }
            $0.filesClient.fetchTextContent = { _, _ in "theirs" }
        }
        store.exhaustivity = .off

        await store.send(.textSaveTapped("mine"))
        await store.receive(\.textSaveResponse)
        await store.send(.textSaveReloadTapped)
        await store.receive(\.textContentResponse.success)

        #expect(store.state.textContent == "theirs")
        #expect(store.state.textSaveConflict == nil)
        #expect(store.state.isTextSaveConflictPresented == false)
        #expect(store.state.textSaveError == nil)
    }

    // MARK: Refetch after a mutation timeout

    @Test
    func aTimedOutDeleteRefetchesTheFolderInsteadOfAssumingFailure() async {
        let browseCalls = LockIsolated(0)
        let store = TestStore(initialState: loadedState(items: [file("a.txt")])) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.browse = { _, path in
                browseCalls.withValue { $0 += 1 }
                return BrowseResult(items: [], access: Self.access, path: path)
            }
            $0.filesClient.favorites = { _ in [] }
        }
        store.exhaustivity = .off

        await store.send(.deleteResponse(.failure(.timedOut)))
        await store.receive(\.itemsResponse.success)
        await store.finish()

        #expect(browseCalls.value == 1)
        #expect(store.state.items.isEmpty)
        #expect(store.state.fileActionErrorMessage == FilesClientError.timedOut.userMessage)
    }

    @Test
    func aTimedOutTransferRefetchesTheFolder() async {
        let browseCalls = LockIsolated(0)
        let store = TestStore(initialState: loadedState(items: [file("a.txt")])) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.browse = { _, path in
                browseCalls.withValue { $0 += 1 }
                return BrowseResult(items: [file("a.txt"), file("a (2).txt")], access: Self.access, path: path)
            }
            $0.filesClient.favorites = { _ in [] }
        }
        store.exhaustivity = .off

        await store.send(.transferResponse(.failure(.timedOut)))
        await store.receive(\.itemsResponse.success)
        await store.finish()

        #expect(browseCalls.value == 1)
        #expect(store.state.items.count == 2)
        #expect(store.state.transferErrorMessage == FilesClientError.timedOut.userMessage)
    }

    @Test
    func anOrdinaryServerFailureDoesNotRefetch() async {
        let store = TestStore(initialState: loadedState(items: [file("a.txt")])) {
            BrowseFeature()
        }

        await store.send(.deleteResponse(.failure(.server(statusCode: 500)))) {
            $0.fileActionErrorMessage = FilesClientError.server(statusCode: 500).userMessage
        }
    }
}
