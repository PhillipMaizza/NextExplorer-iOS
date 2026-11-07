import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import NetworkClient
import Testing

// Serialized: every store shares the sync effect's cancel id, so parallel tests would cancel each other.
@Suite(.serialized)
@MainActor
struct OfflineDownloadsFeatureTests {
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
    func startDownloadWalksTheTreeDownloadsEveryFileAndPinsTheRoot() async {
        let offline = OfflineFileStore.inMemory()
        let downloaded = LockIsolated<[String]>([])
        let store = TestStore(initialState: OfflineDownloadsFeature.State(serverURL: serverURL)) {
            OfflineDownloadsFeature()
        } withDependencies: {
            $0.offlineFileStore = offline
            $0.filesClient.flushDownloadConnections = {}
            $0.filesClient.browse = { _, path in
                switch path {
                case "A":
                    BrowseResult(items: [file("a.txt", path: "A", size: 10), folder("B", path: "A")], access: access(), path: path)
                case "A/B":
                    BrowseResult(items: [file("b.txt", path: "A/B", size: 20)], access: access(), path: path)
                default:
                    BrowseResult(items: [], access: access(), path: path)
                }
            }
            $0.filesClient.offlineDownloadFile = { _, item, _ in
                downloaded.withValue { $0.append(item.id) }
                return URL(fileURLWithPath: "/tmp/\(item.name)")
            }
        }
        store.exhaustivity = .off

        await store.send(.startDownload([folder("A")]))
        await store.receive(\.completed)

        #expect(store.state.progress.phase == .completed)
        #expect(store.state.progress.filesTotal == 2)
        #expect(store.state.progress.filesDone == 2)
        #expect(store.state.progress.fractionComplete == 1)
        #expect(Set(downloaded.value) == ["A/a.txt", "A/B/b.txt"])
        #expect(offline.pinnedRoots().map(\.path) == ["A"])
    }

    @Test
    func resyncReDownloadsThePinnedRoots() async {
        let offline = OfflineFileStore.inMemory()
        offline.setPinnedRoots([OfflinePinnedRoot(path: "A", isDirectory: true)])
        let downloaded = LockIsolated<[String]>([])
        let store = TestStore(initialState: OfflineDownloadsFeature.State(serverURL: serverURL)) {
            OfflineDownloadsFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.offlineFileStore = offline
            $0.filesClient.flushDownloadConnections = {}
            $0.filesClient.browse = { _, path in
                path == "A"
                    ? BrowseResult(items: [file("a.txt", path: "A", size: 5)], access: access(), path: path)
                    : BrowseResult(items: [], access: access(), path: path)
            }
            $0.filesClient.offlineDownloadFile = { _, item, _ in
                downloaded.withValue { $0.append(item.id) }
                return URL(fileURLWithPath: "/tmp/\(item.name)")
            }
        }
        store.exhaustivity = .off

        await store.send(.resyncTapped)
        await store.receive(\.completed)
        #expect(downloaded.value == ["A/a.txt"])
    }

    @Test
    func autoSyncDownloadsOnlyTheNewFilesInPinnedFolders() async {
        let offline = OfflineFileStore.inMemory(localURLs: ["A/old.txt": URL(fileURLWithPath: "/tmp/old.txt")])
        offline.setPinnedRoots([OfflinePinnedRoot(path: "A", isDirectory: true)])
        let downloaded = LockIsolated<[String]>([])
        let store = TestStore(initialState: OfflineDownloadsFeature.State(serverURL: serverURL)) {
            OfflineDownloadsFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.offlineFileStore = offline
            $0.filesClient.flushDownloadConnections = {}
            $0.filesClient.browse = { _, path in
                path == "A"
                    ? BrowseResult(items: [file("old.txt", path: "A"), file("new.txt", path: "A")], access: access(), path: path)
                    : BrowseResult(items: [], access: access(), path: path)
            }
            $0.filesClient.offlineDownloadFile = { _, item, _ in
                downloaded.withValue { $0.append(item.id) }
                return URL(fileURLWithPath: "/tmp/\(item.name)")
            }
        }
        store.exhaustivity = .off

        await store.send(.autoSync(force: false))
        await store.receive(\.completed)
        #expect(downloaded.value == ["A/new.txt"]) // old.txt already offline, skipped
    }

    @Test
    func autoSyncIsThrottledButAForcedSyncBypassesIt() async {
        let offline = OfflineFileStore.inMemory(localURLs: [:])
        offline.setPinnedRoots([OfflinePinnedRoot(path: "A", isDirectory: true)])
        offline.setLastAutoSyncAt(Date(timeIntervalSince1970: 1000))
        let downloaded = LockIsolated<[String]>([])
        let store = TestStore(initialState: OfflineDownloadsFeature.State(serverURL: serverURL)) {
            OfflineDownloadsFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 1100)) // 100s later, under the 300s throttle
            $0.offlineFileStore = offline
            $0.filesClient.flushDownloadConnections = {}
            $0.filesClient.browse = { _, path in
                path == "A"
                    ? BrowseResult(items: [file("new.txt", path: "A")], access: access(), path: path)
                    : BrowseResult(items: [], access: access(), path: path)
            }
            $0.filesClient.offlineDownloadFile = { _, item, _ in
                downloaded.withValue { $0.append(item.id) }
                return URL(fileURLWithPath: "/tmp/\(item.name)")
            }
        }
        store.exhaustivity = .off

        // Throttled: too soon since the last sync, so it no-ops.
        await store.send(.autoSync(force: false))
        #expect(downloaded.value.isEmpty)
        #expect(store.state.progress.phase == .idle)

        // Forced (a reconnect): runs regardless of the throttle.
        await store.send(.autoSync(force: true))
        await store.receive(\.completed)
        #expect(downloaded.value == ["A/new.txt"])
    }

    @Test
    func theInterruptedMarkerClearsWhenADownloadCompletes() async {
        let offline = OfflineFileStore.inMemory()
        let store = TestStore(initialState: OfflineDownloadsFeature.State(serverURL: serverURL)) {
            OfflineDownloadsFeature()
        } withDependencies: {
            $0.offlineFileStore = offline
            $0.filesClient.flushDownloadConnections = {}
            $0.filesClient.browse = { _, _ in BrowseResult(items: [file("a.txt", path: "A")], access: access(), path: "A") }
            $0.filesClient.offlineDownloadFile = { _, _, _ in URL(fileURLWithPath: "/tmp/a.txt") }
        }
        store.exhaustivity = .off

        await store.send(.startDownload([folder("A")]))
        await store.receive(\.completed)
        #expect(offline.wasInterrupted() == false)
    }

    @Test
    func autoSyncStaysSilentWhenNothingIsNew() async {
        let offline = OfflineFileStore.inMemory(localURLs: ["A/a.txt": URL(fileURLWithPath: "/tmp/a.txt")])
        offline.setPinnedRoots([OfflinePinnedRoot(path: "A", isDirectory: true)])
        let store = TestStore(initialState: OfflineDownloadsFeature.State(serverURL: serverURL)) {
            OfflineDownloadsFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.offlineFileStore = offline
            $0.filesClient.flushDownloadConnections = {}
            $0.filesClient.browse = { _, path in
                path == "A"
                    ? BrowseResult(items: [file("a.txt", path: "A")], access: access(), path: path)
                    : BrowseResult(items: [], access: access(), path: path)
            }
        }
        store.exhaustivity = .off

        await store.send(.autoSync(force: false))
        #expect(store.state.progress.phase == .idle)
    }

    @Test
    func cancellingAFreshDownloadRollsBackItsNewlyAddedPins() async {
        let offline = OfflineFileStore.inMemory()
        let store = TestStore(initialState: OfflineDownloadsFeature.State(serverURL: serverURL)) {
            OfflineDownloadsFeature()
        } withDependencies: {
            $0.offlineFileStore = offline
            $0.filesClient.flushDownloadConnections = {}
            $0.filesClient.browse = { _, _ in
                BrowseResult(items: [file("a.txt", path: "A", size: 10)], access: access(), path: "A")
            }
            // A cancellable hang, so the run is still in flight when the cancel arrives.
            $0.filesClient.offlineDownloadFile = { _, item, _ in
                try await Task.sleep(for: .seconds(3600))
                return URL(fileURLWithPath: "/tmp/\(item.name)")
            }
        }
        store.exhaustivity = .off

        await store.send(.startDownload([folder("A")]))
        // Pins are written up front (so an app kill can resume).
        await store.receive(\.prepared)
        #expect(offline.pinnedRoots().map(\.path) == ["A"])

        await store.send(.cancelTapped)
        await store.finish()
        // A user cancel rolls the just-added pin back, so the manage screen doesn't show a phantom
        // "downloaded" folder that has no files.
        #expect(offline.pinnedRoots().isEmpty)
    }

    @Test
    func startDownloadWithNoRootsIsANoOp() async {
        let store = TestStore(initialState: OfflineDownloadsFeature.State(serverURL: serverURL)) {
            OfflineDownloadsFeature()
        }

        await store.send(.startDownload([]))
        #expect(store.state.progress.phase == .idle)
    }

    @Test
    func anUnreadableSubfolderIsSkippedNotFatal() async {
        let offline = OfflineFileStore.inMemory()
        let downloaded = LockIsolated<[String]>([])
        let store = TestStore(initialState: OfflineDownloadsFeature.State(serverURL: serverURL)) {
            OfflineDownloadsFeature()
        } withDependencies: {
            $0.offlineFileStore = offline
            $0.filesClient.flushDownloadConnections = {}
            $0.filesClient.browse = { _, path in
                switch path {
                case "A":
                    BrowseResult(items: [file("a.txt", path: "A", size: 10), folder("Locked", path: "A")], access: access(), path: path)
                case "A/Locked":
                    throw FilesClientError.forbidden(message: nil)
                default:
                    BrowseResult(items: [], access: access(), path: path)
                }
            }
            $0.filesClient.offlineDownloadFile = { _, item, _ in
                downloaded.withValue { $0.append(item.id) }
                return URL(fileURLWithPath: "/tmp/\(item.name)")
            }
        }
        store.exhaustivity = .off

        await store.send(.startDownload([folder("A")]))
        await store.receive(\.completed)

        #expect(store.state.progress.phase == .completed)
        #expect(downloaded.value == ["A/a.txt"])
    }

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
        let store = TestStore(initialState: OfflineDownloadsFeature.State(serverURL: serverURL)) {
            OfflineDownloadsFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.offlineFileStore = offline
            $0.filesClient.flushDownloadConnections = {}
            $0.filesClient.browse = { _, path in
                switch path {
                case "A":
                    BrowseResult(items: [file("a.txt", path: "A"), folder("Slow", path: "A")], access: access(), path: path)
                default:
                    throw FilesClientError.offline
                }
            }
        }
        store.exhaustivity = .off

        await store.send(.resyncTapped)
        await store.receive(\.waitingForNetwork)
        #expect(slots.value == ["A/a.txt", "A/Slow/b.txt"])
    }

    @Test
    func aSyncWhereEveryFolderFailsKeepsEverySlotAndShowsWaiting() async {
        let (offline, slots) = storeWithSlots(["A/a.txt", "A/Sub/b.txt"])
        let store = TestStore(initialState: OfflineDownloadsFeature.State(serverURL: serverURL)) {
            OfflineDownloadsFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.offlineFileStore = offline
            $0.filesClient.flushDownloadConnections = {}
            $0.filesClient.browse = { _, _ in throw FilesClientError.offline }
        }
        store.exhaustivity = .off

        await store.send(.resyncTapped)
        await store.receive(\.waitingForNetwork)
        #expect(slots.value == ["A/a.txt", "A/Sub/b.txt"])
        #expect(store.state.progress.phase == .waitingForNetwork)
    }

    @Test
    func aCompleteWalkStillPrunesFilesTheServerNoLongerLists() async {
        let (offline, slots) = storeWithSlots(["A/a.txt", "A/gone.txt"])
        let store = TestStore(initialState: OfflineDownloadsFeature.State(serverURL: serverURL)) {
            OfflineDownloadsFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.offlineFileStore = offline
            $0.filesClient.flushDownloadConnections = {}
            $0.filesClient.browse = { _, path in
                BrowseResult(items: [file("a.txt", path: "A")], access: access(), path: path)
            }
        }
        store.exhaustivity = .off

        await store.send(.resyncTapped)
        await store.receive(\.completed)
        #expect(slots.value == ["A/a.txt"])
    }

    private func syncStore(
        offline: OfflineFileStore, error: FilesClientError
    ) -> TestStoreOf<OfflineDownloadsFeature> {
        let store = TestStore(initialState: OfflineDownloadsFeature.State(serverURL: serverURL)) {
            OfflineDownloadsFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.offlineFileStore = offline
            $0.filesClient.flushDownloadConnections = {}
            $0.filesClient.browse = { _, _ in throw error }
        }
        store.exhaustivity = .off
        return store
    }

    @Test
    func aPinnedFolderDeletedOnTheServerIsUnpinnedAndTheSyncFinishesNormally() async {
        let offline = OfflineFileStore.inMemory()
        offline.setPinnedRoots([OfflinePinnedRoot(path: "A", isDirectory: true), OfflinePinnedRoot(path: "B", isDirectory: true)])
        let store = syncStore(offline: offline, error: .server(statusCode: 404))

        await store.send(.resyncTapped)
        await store.receive(\.completed)

        #expect(offline.pinnedRoots().isEmpty)
        #expect(store.state.progress.phase == .completed)
    }

    @Test
    func aForbiddenPinnedFolderKeepsItsPinAndReportsAnAccessMessage() async {
        let offline = OfflineFileStore.inMemory()
        offline.setPinnedRoots([OfflinePinnedRoot(path: "A", isDirectory: true)])
        let store = syncStore(offline: offline, error: .forbidden(message: nil))

        await store.send(.resyncTapped)
        await store.receive(\.failed)

        #expect(offline.pinnedRoots().map(\.path) == ["A"])
        #expect(store.state.progress.phase != .waitingForNetwork)
    }

    @Test(arguments: [FilesClientError.offline, .timedOut, .server(statusCode: 500), .server(statusCode: 503)])
    func offlineTimeoutAndServerErrorsStayIncompleteAndKeepThePin(error: FilesClientError) async {
        let offline = OfflineFileStore.inMemory()
        offline.setPinnedRoots([OfflinePinnedRoot(path: "A", isDirectory: true)])
        let store = syncStore(offline: offline, error: error)

        await store.send(.resyncTapped)
        await store.receive(\.waitingForNetwork)

        #expect(offline.pinnedRoots().map(\.path) == ["A"])
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
                            items: [folder("Gone", path: "A"), folder("Locked", path: "A"), folder("Down", path: "A"), file("a.txt", path: "A")],
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
                        BrowseResult(items: [file("a.txt", path: "A"), folder("Bad", path: "A")], access: access(), path: path)
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
        let offline = OfflineFileStore.inMemory()
        offline.setPinnedRoots([OfflinePinnedRoot(path: "A", isDirectory: true)])
        let browseCalls = LockIsolated(0)
        let store = TestStore(initialState: OfflineDownloadsFeature.State(serverURL: serverURL)) {
            OfflineDownloadsFeature()
        } withDependencies: {
            $0.connectivity = ConnectivityClient(isOnline: { false }, events: { AsyncStream { _ in } })
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.offlineFileStore = offline
            $0.filesClient.browse = { _, path in
                browseCalls.withValue { $0 += 1 }
                return BrowseResult(items: [], access: access(), path: path)
            }
        }

        await store.send(.autoSync(force: true))
        #expect(browseCalls.value == 0)
        #expect(store.state.progress.phase == .idle)
    }

    @Test
    func aPinnedRootThatCannotBeListedWaitsForNetworkInsteadOfCompleting() async {
        let offline = OfflineFileStore.inMemory()
        let store = TestStore(initialState: OfflineDownloadsFeature.State(serverURL: serverURL)) {
            OfflineDownloadsFeature()
        } withDependencies: {
            $0.offlineFileStore = offline
            $0.filesClient.flushDownloadConnections = {}
            $0.filesClient.browse = { _, _ in throw FilesClientError.offline }
        }
        store.exhaustivity = .off

        await store.send(.startDownload([folder("A")]))
        await store.receive(\.waitingForNetwork)

        #expect(store.state.progress.phase == .waitingForNetwork)
        #expect(offline.pinnedRoots().map(\.path) == ["A"])
        #expect(offline.wasInterrupted() == false)
    }
}
