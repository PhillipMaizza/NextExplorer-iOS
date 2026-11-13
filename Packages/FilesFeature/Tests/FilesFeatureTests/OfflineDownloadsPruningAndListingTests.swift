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
    func aCompleteWalkKeepsFilesTheServerNoLongerLists() async {
        let (offline, slots) = storeWithSlots(["A/a.txt", "A/gone.txt"])
        let run = makeRun(
            offline: offline,
            browse: { [self] path in listing([file(TestFile.aText, path: "A")], path: path) }
        )

        await run.store.send(.resyncTapped).finish()

        #expect(run.phase == .completed)
        #expect(slots.value == ["A/a.txt", "A/gone.txt"], "A file deleted online stays until the user removes it")
    }

    @Test
    func aSyncOnlyDropsOrphansOfUnpinnedRootsNeverWhatTheServerLost() async {
        let offline = pinnedStore(["A"])
        let calls = LockIsolated<[Bool]>([])
        var watched = offline
        watched.reconcile = { current in calls.withValue { $0.append(current == nil) } }
        let run = makeRun(
            offline: watched,
            browse: { [self] path in listing([file(TestFile.aText, path: "A")], path: path) }
        )

        await run.store.send(.resyncTapped).finish()

        #expect(calls.value == [true], "Reconciled once, with no list of what the server still has")
    }

    /// Answers a pinned folder with `rootError` and everything else (its parent) with `parent`.
    private func goneRun(
        offline: OfflineFileStore, rootError: FilesClientError,
        parent: @escaping @Sendable () throws -> BrowseResult
    ) -> Run {
        makeRun(offline: offline) { path in
            guard path.isEmpty else { throw rootError }
            return try parent()
        }
    }

    @Test(arguments: [
        FilesClientError.server(statusCode: 404),
        .serverMessage(statusCode: 404, message: "Share expired"),
        .serverMessage(statusCode: 404, message: "Access denied"),
        .serverMessage(statusCode: 404, message: "Path not found."),
    ])
    func aPinnedFolderDeletedOnTheServerKeepsItsPinAndItsFiles(rootError: FilesClientError) async {
        let (offline, slots) = storeWithSlots(["A/a.txt", "A/Sub/b.txt"])
        let run = goneRun(offline: offline, rootError: rootError) { [self] in listing([folder("B")]) }

        await run.store.send(.resyncTapped).finish()

        #expect(offline.pinnedRoots() == [OfflinePinnedRoot(path: "A", isDirectory: true)])
        #expect(slots.value == ["A/a.txt", "A/Sub/b.txt"])
        #expect(run.phase == .completed, "A folder the server lost is not an error to report")
    }

    @Test
    func aFolderStaysPinnedHoweverManySyncsFindItGone() async {
        let (offline, slots) = storeWithSlots(["A/a.txt"])
        let run = goneRun(offline: offline, rootError: .server(statusCode: 404)) { [self] in listing([]) }

        for _ in 0 ..< 4 {
            await run.store.send(.resyncTapped).finish()
        }

        #expect(offline.pinnedRoots() == [OfflinePinnedRoot(path: "A", isDirectory: true)])
        #expect(slots.value == ["A/a.txt"])
    }

    @Test
    func aFolderThatComesBackIsSyncedAgain() async {
        let isGone = LockIsolated(true)
        let downloaded = LockIsolated<[String]>([])
        let offline = pinnedStore(["A"])
        let run = makeRun(
            offline: offline,
            browse: { [self] path in
                if path == "A", isGone.value {
                    throw FilesClientError.server(statusCode: 404)
                }
                return listing(path == "A" ? [file(TestFile.aText, path: "A")] : [], path: path)
            },
            download: { item in
                downloaded.withValue { $0.append(item.id) }
                return URL(fileURLWithPath: "/tmp/\(item.name)")
            }
        )

        await run.store.send(.resyncTapped).finish()
        #expect(downloaded.value.isEmpty)
        isGone.setValue(false)
        await run.store.send(.resyncTapped).finish()

        #expect(downloaded.value == ["A/a.txt"])
        #expect(offline.pinnedRoots() == [OfflinePinnedRoot(path: "A", isDirectory: true)])
    }

    @Test
    func aSubfolderDeletedOnTheServerKeepsItsFilesWhileTheRestSyncs() async {
        let (offline, slots) = storeWithSlots(["A/a.txt", "A/Gone/b.txt"])
        let run = makeRun(offline: offline) { [self] path in
            guard path == "A" else { throw FilesClientError.server(statusCode: 404) }
            return listing([file(TestFile.aText, path: "A"), folder(Constants.missingFolder, path: "A")], path: path)
        }

        await run.store.send(.resyncTapped).finish()

        #expect(run.phase == .completed)
        #expect(slots.value == ["A/a.txt", "A/Gone/b.txt"])
        #expect(offline.pinnedRoots() == [OfflinePinnedRoot(path: "A", isDirectory: true)])
    }

    @Test
    func aFailedListingStillShowsWaitingForTheNetworkAndKeepsEverything() async {
        let (offline, slots) = storeWithSlots(["A/a.txt"])
        let hold = BrowseHold()
        let store = makeStore(hold: hold, offline: offline) { _ in throw FilesClientError.timedOut }

        await resync(store, hold: hold)
        await receiveWaiting(store)

        #expect(slots.value == ["A/a.txt"])
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
                            items: [
                                folder(Constants.missingFolder, path: "A"),
                                folder("Locked", path: "A"),
                                folder("Down", path: "A"),
                                file(TestFile.aText, path: "A"),
                            ],
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
                        BrowseResult(
                            items: [file(TestFile.aText, path: "A"), folder("Bad", path: "A")],
                            access: access(),
                            path: path
                        )
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
        let store = makeStore(
            state,
            hold: BrowseHold(),
            offline: offline,
            browse: { [self] path in listing([], path: path) }
        )

        await store.send(.removeAllOfflineTapped) { $0.$progress.withLock { $0 = OfflineDownloadProgress() } }
        await store.finish()

        #expect(removals.value == 1)
    }
}

private enum Constants {
    static let missingFolder = "Gone"
}
