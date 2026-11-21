import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Testing
import TestUtils

@Suite(.isolatedDependencies)
@MainActor
struct BrowseFolderSizeTests {
    private let docs = BrowseFixtures.folder(TestFolder.docs)
    private let notesFile = BrowseFixtures.file(TestFile.notes, size: 7)

    private func loadedState(mode: FolderSizeMode = .full) -> BrowseFeature.State {
        var state = BrowseFixtures.loadedState(items: [docs, notesFile])
        state.folderSizeMode = mode
        return state
    }

    @Test("A folder size read asks for the folders only and keeps what the server answers")
    func readsTheSizesOfTheFolders() async {
        let asked = LockIsolated<[String]>([])
        let store = BrowseFixtures.store(loadedState()) {
            $0.filesClient.folderSizes = { _, paths in
                asked.withValue { $0 = paths }
                return Dictionary(uniqueKeysWithValues: paths.map { (
                    $0,
                    FolderSize(sizeBytes: 2048, isIndexed: true)
                ) })
            }
        }

        await store.send(.folderSizesDue(attempt: 0))
        await store.receive(\.folderSizesResponse) {
            $0.folderSizes = [docs.id: 2048]
        }

        #expect(asked.value == [docs.id])
    }

    @Test("With the feature off nothing is asked and no figure shows")
    func offAsksNothing() async {
        let store = BrowseFixtures.store(loadedState(mode: .off)) {
            $0.filesClient.folderSizes = { _, _ in
                Issue.record("folder sizes are off")
                return [:]
            }
        }

        await store.send(.folderSizesDue(attempt: 0))
        #expect(store.state.folderSizes.isEmpty)
    }

    @Test("A size the server is still working on is read again after a wait, then left alone once settled")
    func dirtySizeIsReadAgainWithBackoff() async {
        let clock = TestClock()
        let calls = LockIsolated(0)
        let store = BrowseFixtures.store(loadedState()) {
            $0.continuousClock = clock
            $0.filesClient.folderSizes = { _, paths in
                let call = calls.withValue { value -> Int in
                    value += 1
                    return value
                }
                return Dictionary(uniqueKeysWithValues: paths.map {
                    ($0, FolderSize(sizeBytes: Int64(call), isIndexed: true, isDirty: call == 1))
                })
            }
        }

        await store.send(.folderSizesDue(attempt: 0))
        await store.receive(\.folderSizesResponse) {
            $0.folderSizes = [docs.id: 1]
        }
        await clock.advance(by: BrowseFeature.folderSizeRetryDelays[0])
        await store.receive(\.folderSizesDue)
        await store.receive(\.folderSizesResponse) {
            $0.folderSizes = [docs.id: 2]
        }
        #expect(calls.value == 2)
    }

    @Test("A folder the indexer has not reached loses any figure it had")
    func unindexedFolderShowsNothing() async {
        var state = loadedState()
        state.folderSizes[docs.id] = 512
        let store = BrowseFixtures.store(state) {
            $0.filesClient.folderSizes = { _, paths in
                Dictionary(uniqueKeysWithValues: paths.map { ($0, FolderSize()) })
            }
        }

        await store.send(.folderSizesDue(attempt: 0))
        await store.receive(\.folderSizesResponse) {
            $0.folderSizes = [:]
        }
    }

    @Test("A refused rescan does not stop the read of another folder's rescan")
    func refusedRescanKeepsTheOthersPolling() async {
        let other = BrowseFixtures.folder("Other")
        var state = loadedState()
        state.items.append(other)
        state.refreshingFolderSizeIDs = [docs.id]
        let store = BrowseFixtures.store(state) {
            $0.filesClient.refreshFolderSize = { _, _ in throw FilesClientError.rateLimited }
        }

        await store.send(.folderSizeRefreshTapped(other.id)) {
            $0.refreshingFolderSizeIDs = [docs.id, other.id]
        }
        await store.receive(\.folderSizeRefreshResponse) {
            $0.refreshingFolderSizeIDs = [docs.id]
            $0.fileActionErrorMessage = FilesClientError.rateLimited.userMessage
        }
    }

    @Test("A copy or move into a folder on screen reads the sizes again")
    func contentsChangedReadsAgain() async {
        let store = BrowseFixtures.store(loadedState()) {
            $0.filesClient.folderSizes = { _, paths in
                Dictionary(uniqueKeysWithValues: paths.map { ($0, FolderSize(sizeBytes: 7, isIndexed: true)) })
            }
        }

        await store.send(.delegate(.directoryContentsChanged))
        await store.receive(\.folderSizesResponse) {
            $0.folderSizes = [docs.id: 7]
        }
    }

    @Test("A 404 from the sizes route means the server turned the feature off, so it is remembered")
    func missingRouteTurnsTheFeatureOff() async {
        var state = loadedState()
        state.folderSizes[docs.id] = 5
        let store = BrowseFixtures.store(state) {
            $0.filesClient.folderSizes = { _, _ in
                throw FilesClientError.serverMessage(statusCode: 404, message: "off")
            }
        }

        await store.send(.folderSizesDue(attempt: 0))
        await store.receive(\.folderSizesUnavailable) {
            $0.folderSizeMode = .off
            $0.folderSizes = [:]
        }
    }

    @Test("Sorting by size orders a folder by its counted size, not zero")
    func sortsFoldersByTheirCountedSize() {
        let big = BrowseFixtures.folder("Big")
        let small = BrowseFixtures.folder("Small")
        let sorted = BrowseFeature.sorted(
            [small, big],
            by: .size,
            direction: .descending,
            folderSizes: [big.id: 900, small.id: 10]
        )
        #expect(sorted.map(\.name) == ["Big", "Small"])
    }

    @Test("A rescan is asked for the folder, then its size is read back")
    func refreshAsksThenReads() async {
        let refreshed = LockIsolated<[String]>([])
        let clock = TestClock()
        let store = BrowseFixtures.store(loadedState()) {
            $0.continuousClock = clock
            $0.filesClient.refreshFolderSize = { _, path in
                refreshed.withValue { $0.append(path) }
                return FolderSize(sizeBytes: 1, isIndexed: true, isDirty: true)
            }
            $0.filesClient.folderSizes = { _, paths in
                Dictionary(uniqueKeysWithValues: paths.map { ($0, FolderSize(sizeBytes: 9, isIndexed: true)) })
            }
        }

        await store.send(.folderSizeRefreshTapped(docs.id)) {
            $0.refreshingFolderSizeIDs = [docs.id]
        }
        await store.receive(\.folderSizeRefreshResponse)
        await store.receive(\.folderSizesResponse) {
            $0.folderSizes = [docs.id: 9]
        }
        // The read repeats on its backoff while the rescan runs, then stops.
        let delays = BrowseFeature.folderSizeRetryDelays
        for (index, delay) in delays.enumerated() {
            await clock.advance(by: delay)
            await store.receive(\.folderSizesDue)
            if index == delays.count - 1 {
                await store.receive(\.folderSizesResponse) {
                    $0.refreshingFolderSizeIDs = []
                }
            } else {
                await store.receive(\.folderSizesResponse)
            }
        }
        #expect(refreshed.value == [docs.id])
    }

    @Test("A refused rescan is reported and clears the waiting")
    func refusedRefreshIsReported() async {
        let store = BrowseFixtures.store(loadedState()) {
            $0.filesClient.refreshFolderSize = { _, _ in
                throw FilesClientError.serverMessage(statusCode: 400, message: "Excluded.")
            }
        }

        await store.send(.folderSizeRefreshTapped(docs.id)) {
            $0.refreshingFolderSizeIDs = [docs.id]
        }
        await store.receive(\.folderSizeRefreshResponse) {
            $0.refreshingFolderSizeIDs = []
            $0.fileActionErrorMessage = "Excluded."
        }
    }

    @Test("A rescan of a file, or with the feature off, is ignored")
    func refreshIgnoredWhenNotAFolderOrOff() async {
        let store = BrowseFixtures.store(loadedState()) {
            $0.filesClient.refreshFolderSize = { _, _ in
                Issue.record("nothing should be asked")
                return FolderSize()
            }
        }
        await store.send(.folderSizeRefreshTapped(notesFile.id))

        store.exhaustivity = .on
        let off = BrowseFixtures.store(loadedState(mode: .off)) {
            $0.filesClient.refreshFolderSize = { _, _ in
                Issue.record("nothing should be asked")
                return FolderSize()
            }
        }
        await off.send(.folderSizeRefreshTapped(docs.id))
    }

    @Test("The server's answer for the mode is kept for the folders pushed later")
    func modeIsRememberedAcrossScreens() async {
        let cache = JSONCacheStore.inMemory()
        let store = TestStore(initialState: withDependencies { $0.jsonCacheStore = cache } operation: {
            BrowseFixtures.state()
        }) {
            BrowseFeature()
        } withDependencies: {
            $0.jsonCacheStore = cache
        }

        await store.send(.serverFeaturesResponse(ServerFeatures(folderSizeMode: .shallow))) {
            $0.folderSizeMode = .shallow
        }
        await store.finish()

        let pushed = withDependencies { $0.jsonCacheStore = cache } operation: {
            BrowseFixtures.state(TestFolder.docs, title: TestFolder.docs)
        }
        #expect(pushed.folderSizeMode == .shallow)
    }
}
