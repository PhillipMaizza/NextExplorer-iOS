import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Localization
import NetworkClient
import Testing
import TestUtils

@Suite(.isolatedDependencies)
@MainActor
struct OfflineDownloadsPruningAndListingTests: OfflineDownloadsTestSupport {
    private func storeWithSlots(_ paths: Set<String>) -> (store: OfflineFileStore, slots: LockIsolated<Set<String>>) {
        let slots = LockIsolated(paths)
        var offline = OfflineFileStore.inMemory(
            localURLs: Dictionary(uniqueKeysWithValues: paths.map { ($0, URL(fileURLWithPath: "/tmp/\($0)")) })
        )
        offline.setPinnedRoots([OfflinePinnedRoot(path: "A", isDirectory: true)])
        offline.reconcile = { current in
            guard let current else { return }
            slots.withValue { $0 = $0.intersection(current) }
        }
        return (offline, slots)
    }

    @Test
    func aSyncWithOneFailedSubfolderNeverPrunesOfflineSlots() async {
        let (offline, slots) = storeWithSlots(["A/a.txt", "A/Slow/b.txt"])
        let hold = BrowseHold()
        let store = makeStore(hold: hold, offline: offline) { [self] path in
            guard path == "A" else { throw FilesClientError.offline }
            return listing([file(TestFile.aText, path: "A"), folder("Slow", path: "A")], path: path)
        }

        await resync(store, hold: hold)
        await receiveWaiting(store)

        #expect(slots.value == ["A/a.txt", "A/Slow/b.txt"])
    }

    @Test
    func aSyncWhereEveryFolderFailsKeepsEverySlotAndShowsWaiting() async {
        let (offline, slots) = storeWithSlots(["A/a.txt", "A/Sub/b.txt"])
        let hold = BrowseHold()
        let store = makeStore(hold: hold, offline: offline) { _ in throw FilesClientError.offline }

        await resync(store, hold: hold)
        await receiveWaiting(store)

        #expect(slots.value == ["A/a.txt", "A/Sub/b.txt"])
        #expect(store.state.progress.phase == .waitingForNetwork)
    }

    @Test
    func aCompleteWalkStillPrunesFilesTheServerNoLongerLists() async {
        let (offline, slots) = storeWithSlots(["A/a.txt", "A/gone.txt"])
        let run = makeRun(offline: offline, browse: { [self] path in listing([file(TestFile.aText, path: "A")], path: path) })

        await run.store.send(.resyncTapped).finish()

        #expect(run.phase == .completed)
        #expect(slots.value == ["A/a.txt"])
    }

    /// Answers `A` and `B` with `rootError`, and the parent of a pinned folder with `parent`.
    private func notFoundStore(
        offline: OfflineFileStore, hold: BrowseHold, rootError: FilesClientError, parent: @escaping @Sendable () throws -> BrowseResult
    ) -> Harness {
        makeStore(hold: hold, offline: offline) { path in
            guard path.isEmpty else { throw rootError }
            return try parent()
        }
    }

    @Test
    func aSingleNotFoundNeverUnpinsAFolderWhoseParentCannotBeListed() async {
        let offline = pinnedStore(["A"])
        let hold = BrowseHold()
        let store = notFoundStore(offline: offline, hold: hold, rootError: .server(statusCode: 404)) { throw FilesClientError.offline }

        await resync(store, hold: hold)
        await receiveWaiting(store)

        #expect(offline.pinnedRoots() == [OfflinePinnedRoot(path: "A", isDirectory: true)])
        #expect(store.state.progress.phase == .waitingForNetwork)
    }

    @Test
    func aTransientNotFoundKeepsTheFilesUnderTheFolder() async {
        let (offline, slots) = storeWithSlots(["A/a.txt", "A/Sub/b.txt"])
        let hold = BrowseHold()
        let store = notFoundStore(offline: offline, hold: hold, rootError: .server(statusCode: 404)) { throw FilesClientError.timedOut }

        await resync(store, hold: hold)
        await receiveWaiting(store)

        #expect(slots.value == ["A/a.txt", "A/Sub/b.txt"])
        #expect(offline.pinnedRoots() == [OfflinePinnedRoot(path: "A", isDirectory: true)])
    }

    @Test
    func aFolderTheParentListingOmitsIsUnpinnedAndTheUserIsToldWhich() async {
        let offline = pinnedStore(["A", "B"])
        let hold = BrowseHold()
        let store = notFoundStore(offline: offline, hold: hold, rootError: .server(statusCode: 404)) { [self] in
            listing([folder("B")])
        }

        await resync(store, hold: hold)
        await store.receive(\.pinsRemoved) {
            $0.$progress.withLock { $0.phase = .failed(L10n.Offline.pinRemoved("A")) }
        }

        #expect(offline.pinnedRoots() == [OfflinePinnedRoot(path: "B", isDirectory: true)])
        #expect(!store.state.progress.isActive)
    }

    @Test
    func aFolderTheParentListingStillShowsKeepsItsPinAndItsStrikes() async {
        let offline = pinnedStore(["A"])
        let hold = BrowseHold()
        let store = notFoundStore(offline: offline, hold: hold, rootError: .server(statusCode: 404)) { [self] in
            listing([folder("A")])
        }

        await resync(store, hold: hold)
        await receiveWaiting(store)
        await resync(store, hold: hold)
        await receiveWaiting(store)
        await resync(store, hold: hold)
        await receiveWaiting(store)

        #expect(offline.pinnedRoots() == [OfflinePinnedRoot(path: "A", isDirectory: true)])
        #expect(offline.recordMissingRoot("A") == 1, "a folder the parent lists is not missing, so earlier strikes reset")
    }

    @Test
    func twoNotFoundSyncsInARowUnpinAFolderWhoseParentCannotBeListed() async {
        let offline = pinnedStore(["A"])
        let hold = BrowseHold()
        let store = notFoundStore(offline: offline, hold: hold, rootError: .server(statusCode: 404)) { throw FilesClientError.offline }

        await resync(store, hold: hold)
        await receiveWaiting(store)
        #expect(offline.pinnedRoots() == [OfflinePinnedRoot(path: "A", isDirectory: true)])

        await resync(store, hold: hold)
        await store.receive(\.pinsRemoved) {
            $0.$progress.withLock { $0.phase = .failed(L10n.Offline.pinRemoved("A")) }
        }

        #expect(offline.pinnedRoots().isEmpty)
    }

    @Test
    func aSuccessfulListingBetweenTwoNotFoundSyncsResetsTheStrikes() async {
        let offline = pinnedStore(["A"])
        let isHealthy = LockIsolated(false)
        let run = makeRun(offline: offline) { [self] path in
            if isHealthy.value {
                return listing([], path: path)
            }
            throw FilesClientError.server(statusCode: 404)
        }

        await run.store.send(.resyncTapped).finish()
        #expect(run.phase == .waitingForNetwork)
        isHealthy.setValue(true)
        await run.store.send(.resyncTapped).finish()
        #expect(run.phase == .completed)
        isHealthy.setValue(false)
        await run.store.send(.resyncTapped).finish()
        #expect(run.phase == .waitingForNetwork)

        #expect(offline.pinnedRoots() == [OfflinePinnedRoot(path: "A", isDirectory: true)])
    }

    @Test(arguments: ["Access denied", "Path not found.", "path not found", "ACCESS DENIED."])
    func anAccessOrPathNotFoundMessageNeverCountsAsTheFolderBeingGone(message: String) async {
        let offline = pinnedStore(["A"])
        let hold = BrowseHold()
        let store = notFoundStore(offline: offline, hold: hold, rootError: .serverMessage(statusCode: 404, message: message)) {
            throw FilesClientError.offline
        }

        for _ in 0 ..< 3 {
            await resync(store, hold: hold)
            await receiveWaiting(store)
        }

        #expect(offline.pinnedRoots() == [OfflinePinnedRoot(path: "A", isDirectory: true)])
    }

    @Test
    func aNotFoundWithAnotherMessageStillNeedsTwoSyncs() async {
        let offline = pinnedStore(["A"])
        let hold = BrowseHold()
        let store = notFoundStore(offline: offline, hold: hold, rootError: .serverMessage(statusCode: 404, message: "Share expired")) {
            throw FilesClientError.offline
        }

        await resync(store, hold: hold)
        await receiveWaiting(store)
        #expect(offline.pinnedRoots() == [OfflinePinnedRoot(path: "A", isDirectory: true)])
        await resync(store, hold: hold)
        await store.receive(\.pinsRemoved) {
            $0.$progress.withLock { $0.phase = .failed(L10n.Offline.pinRemoved("A")) }
        }

        #expect(offline.pinnedRoots().isEmpty)
    }

    @Test
    func aMissingSubfolderOfAPinnedRootNeverUnpinsAnythingAndLeavesTheWalkIncomplete() async {
        let (offline, slots) = storeWithSlots(["A/a.txt", "A/Gone/b.txt"])
        let hold = BrowseHold()
        let store = makeStore(hold: hold, offline: offline) { [self] path in
            guard path == "A" else { throw FilesClientError.server(statusCode: 404) }
            return listing([file(TestFile.aText, path: "A"), folder(Constants.missingFolder, path: "A")], path: path)
        }

        await resync(store, hold: hold)
        await receiveWaiting(store)

        #expect(slots.value == ["A/a.txt", "A/Gone/b.txt"], "a partial walk never prunes")
        #expect(offline.pinnedRoots() == [OfflinePinnedRoot(path: "A", isDirectory: true)])
    }

    @Test
    func aForbiddenPinnedFolderKeepsItsPinAndReportsAnAccessMessage() async {
        let offline = pinnedStore(["A"])
        let hold = BrowseHold()
        let store = makeStore(hold: hold, offline: offline) { _ in throw FilesClientError.forbidden(message: nil) }

        await resync(store, hold: hold)
        await store.receive(\.failed) {
            $0.$progress.withLock { $0.phase = .failed(FilesClientError.forbidden(message: nil).userMessage) }
        }

        #expect(offline.pinnedRoots() == [OfflinePinnedRoot(path: "A", isDirectory: true)])
    }

    @Test
    func aForbiddenFolderIsSilentForAnAutomaticSync() async {
        let offline = pinnedStore(["A"])
        let hold = BrowseHold()
        let store = makeStore(hold: hold, offline: offline) { _ in throw FilesClientError.forbidden(message: nil) }

        let gate = hold.hold()
        await store.send(.autoSync(force: false))
        gate.open()
        await store.receive(\.autoSyncFailed)

        #expect(offline.pinnedRoots() == [OfflinePinnedRoot(path: "A", isDirectory: true)])
        #expect(store.state.progress.phase == .idle)
    }

    @Test(arguments: [FilesClientError.offline, .timedOut, .server(statusCode: 500), .server(statusCode: 503)])
    func offlineTimeoutAndServerErrorsStayIncompleteAndKeepThePin(error: FilesClientError) async {
        let offline = pinnedStore(["A"])
        let hold = BrowseHold()
        let store = makeStore(hold: hold, offline: offline) { _ in throw error }

        await resync(store, hold: hold)
        await receiveWaiting(store)

        #expect(offline.pinnedRoots() == [OfflinePinnedRoot(path: "A", isDirectory: true)])
        #expect(store.state.progress.phase == .waitingForNetwork)
    }

    @Test
    func walkClassifiesEachFailureOfAFolderListing() async throws {
        let result = try await OfflineDownloadsFeature.walk(
            roots: [folder("A")], serverURL: serverURL,
            filesClient: withDependencies {
                $0.filesClient.browse = { _, path in
                    switch path {
                    case "A":
                        BrowseResult(
                            items: [folder(Constants.missingFolder, path: "A"), folder("Locked", path: "A"), folder("Down", path: "A"), file(TestFile.aText, path: "A")],
                            access: access(), path: path
                        )
                    case "A/Gone": throw FilesClientError.server(statusCode: 404)
                    case "A/Locked": throw FilesClientError.forbidden(message: nil)
                    default: throw FilesClientError.server(statusCode: 502)
                    }
                }
            } operation: {
                @Dependency(\.filesClient) var client
                return client
            }
        )
        #expect(result.goneFolders == ["A/Gone"])
        #expect(result.ambiguousGoneFolders.isEmpty)
        #expect(result.forbiddenFolders == ["A/Locked"])
        #expect(result.failedFolders == ["A/Down"])
        #expect(result.hasIncompleteWalk)
        #expect(result.hasForbiddenFolders)
    }

    @Test
    func walkReportsTheFoldersThatFailedToList() async throws {
        let result = try await OfflineDownloadsFeature.walk(
            roots: [folder("A")], serverURL: serverURL,
            filesClient: withDependencies {
                $0.filesClient.browse = { _, path in
                    switch path {
                    case "A":
                        BrowseResult(items: [file(TestFile.aText, path: "A"), folder("Bad", path: "A")], access: access(), path: path)
                    default:
                        throw FilesClientError.offline
                    }
                }
            } operation: {
                @Dependency(\.filesClient) var client
                return client
            }
        )
        #expect(result.files.map(\.id) == ["A/a.txt"])
        #expect(result.failedFolders == ["A/Bad"])
        #expect(result.hasIncompleteWalk)
    }

    @Test
    func autoSyncDoesNothingWhileOffline() async {
        let offline = pinnedStore(["A"])
        let browseCalls = LockIsolated(0)
        let store = makeStore(
            hold: BrowseHold(),
            offline: offline,
            browse: { [self] path in
                browseCalls.withValue { $0 += 1 }
                return listing([], path: path)
            },
            configure: { $0.connectivity = ConnectivityClient(isOnline: { false }, events: { AsyncStream { _ in } }) }
        )

        await store.send(.autoSync(force: true))
        #expect(browseCalls.value == 0)
        #expect(store.state.progress.phase == .idle)
    }

    @Test
    func removeAllOfflineClearsTheProgressAndTheCurrentAccountsFiles() async {
        let removals = LockIsolated(0)
        var offline = pinnedStore(["A"])
        offline.removeCurrentAccount = { removals.withValue { $0 += 1 } }
        var state = freshState()
        state.$progress.withLock { $0.phase = .completed }
        let store = makeStore(state, hold: BrowseHold(), offline: offline, browse: { [self] path in listing([], path: path) })

        await store.send(.removeAllOfflineTapped) { $0.$progress.withLock { $0 = OfflineDownloadProgress() } }
        await store.finish()

        #expect(removals.value == 1)
    }
}

private enum Constants {
    static let missingFolder = "Gone"
}
