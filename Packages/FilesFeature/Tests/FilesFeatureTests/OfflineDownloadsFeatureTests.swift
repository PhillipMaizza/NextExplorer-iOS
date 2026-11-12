import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Localization
import NetworkClient
import Testing
import TestUtils

// Serialized: every store shares the sync effect's cancel id, so parallel tests would cancel each other.
@Suite(.serialized, .isolatedDependencies)
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
                try await suspendUntilCancelled()
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

    private func pinnedStore(_ paths: [String]) -> OfflineFileStore {
        let offline = OfflineFileStore.inMemory()
        offline.setPinnedRoots(paths.map { OfflinePinnedRoot(path: $0, isDirectory: true) })
        return offline
    }

    /// Answers `A` with `rootError`, and any other folder (a pinned folder's parent) with `parent`.
    private func browseStore(
        offline: OfflineFileStore, rootError: FilesClientError, parent: @escaping @Sendable (String) throws -> BrowseResult
    ) -> TestStoreOf<OfflineDownloadsFeature> {
        let store = TestStore(initialState: OfflineDownloadsFeature.State(serverURL: serverURL)) {
            OfflineDownloadsFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.offlineFileStore = offline
            $0.filesClient.flushDownloadConnections = {}
            $0.filesClient.browse = { _, path in
                guard path.isEmpty else { throw rootError }
                return try parent(path)
            }
        }
        store.exhaustivity = .off
        return store
    }

    private nonisolated func listing(_ items: [FileItem], path: String = "") -> BrowseResult {
        BrowseResult(items: items, access: access(), path: path)
    }

    @Test
    func aSingleNotFoundNeverUnpinsAFolderWhoseParentCannotBeListed() async {
        let offline = pinnedStore(["A"])
        let store = browseStore(offline: offline, rootError: .server(statusCode: 404)) { _ in throw FilesClientError.offline }

        await store.send(.resyncTapped)
        await store.receive(\.waitingForNetwork)

        #expect(offline.pinnedRoots().map(\.path) == ["A"])
        #expect(store.state.progress.phase == .waitingForNetwork)
    }

    @Test
    func aTransientNotFoundKeepsTheFilesUnderTheFolder() async {
        let (offline, slots) = storeWithSlots(["A/a.txt", "A/Sub/b.txt"])
        let store = browseStore(offline: offline, rootError: .server(statusCode: 404)) { _ in throw FilesClientError.timedOut }

        await store.send(.resyncTapped)
        await store.receive(\.waitingForNetwork)

        #expect(slots.value == ["A/a.txt", "A/Sub/b.txt"])
        #expect(offline.pinnedRoots().map(\.path) == ["A"])
    }

    @Test
    func aFolderTheParentListingOmitsIsUnpinnedAndTheUserIsToldWhich() async {
        let offline = pinnedStore(["A", "B"])
        let store = browseStore(offline: offline, rootError: .server(statusCode: 404)) { _ in
            listing([folder("B")])
        }

        await store.send(.resyncTapped)
        await store.receive(\.pinsRemoved)

        #expect(offline.pinnedRoots().map(\.path) == ["B"])
        #expect(store.state.progress.phase == .failed(L10n.Offline.pinRemoved("A")))
        #expect(!store.state.progress.isActive)
    }

    @Test
    func aFolderTheParentListingStillShowsKeepsItsPinAndItsStrikes() async {
        let offline = pinnedStore(["A"])
        let store = browseStore(offline: offline, rootError: .server(statusCode: 404)) { _ in
            listing([folder("A")])
        }

        for _ in 0 ..< 3 {
            await store.send(.resyncTapped)
            await store.receive(\.waitingForNetwork)
        }

        #expect(offline.pinnedRoots().map(\.path) == ["A"])
        #expect(offline.recordMissingRoot("A") == 1, "a folder the parent lists is not missing, so earlier strikes reset")
    }

    @Test
    func twoNotFoundSyncsInARowUnpinAFolderWhoseParentCannotBeListed() async {
        let offline = pinnedStore(["A"])
        let store = browseStore(offline: offline, rootError: .server(statusCode: 404)) { _ in throw FilesClientError.offline }

        await store.send(.resyncTapped)
        await store.receive(\.waitingForNetwork)
        #expect(offline.pinnedRoots().map(\.path) == ["A"])

        await store.send(.resyncTapped)
        await store.receive(\.pinsRemoved)

        #expect(offline.pinnedRoots().isEmpty)
        #expect(store.state.progress.phase == .failed(L10n.Offline.pinRemoved("A")))
    }

    @Test
    func aSuccessfulListingBetweenTwoNotFoundSyncsResetsTheStrikes() async {
        let offline = pinnedStore(["A"])
        let isHealthy = LockIsolated(false)
        let store = TestStore(initialState: OfflineDownloadsFeature.State(serverURL: serverURL)) {
            OfflineDownloadsFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.offlineFileStore = offline
            $0.filesClient.flushDownloadConnections = {}
            $0.filesClient.browse = { _, path in
                if isHealthy.value {
                    return listing([], path: path)
                }
                throw FilesClientError.server(statusCode: 404)
            }
        }
        store.exhaustivity = .off

        await store.send(.resyncTapped)
        await store.receive(\.waitingForNetwork)
        isHealthy.setValue(true)
        await store.send(.resyncTapped)
        await store.receive(\.completed)
        isHealthy.setValue(false)
        await store.send(.resyncTapped)
        await store.receive(\.waitingForNetwork)

        #expect(offline.pinnedRoots().map(\.path) == ["A"])
    }

    @Test(arguments: ["Access denied", "Path not found.", "path not found", "ACCESS DENIED."])
    func anAccessOrPathNotFoundMessageNeverCountsAsTheFolderBeingGone(message: String) async {
        let offline = pinnedStore(["A"])
        let store = browseStore(offline: offline, rootError: .serverMessage(statusCode: 404, message: message)) { _ in
            throw FilesClientError.offline
        }

        for _ in 0 ..< 3 {
            await store.send(.resyncTapped)
            await store.receive(\.waitingForNetwork)
        }

        #expect(offline.pinnedRoots().map(\.path) == ["A"])
    }

    @Test
    func aNotFoundWithAnotherMessageStillNeedsTwoSyncs() async {
        let offline = pinnedStore(["A"])
        let store = browseStore(offline: offline, rootError: .serverMessage(statusCode: 404, message: "Share expired")) { _ in
            throw FilesClientError.offline
        }

        await store.send(.resyncTapped)
        await store.receive(\.waitingForNetwork)
        #expect(offline.pinnedRoots().map(\.path) == ["A"])
        await store.send(.resyncTapped)
        await store.receive(\.pinsRemoved)

        #expect(offline.pinnedRoots().isEmpty)
    }

    @Test
    func aMissingSubfolderOfAPinnedRootNeverUnpinsAnythingAndLeavesTheWalkIncomplete() async {
        let (offline, slots) = storeWithSlots(["A/a.txt", "A/Gone/b.txt"])
        let store = TestStore(initialState: OfflineDownloadsFeature.State(serverURL: serverURL)) {
            OfflineDownloadsFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.offlineFileStore = offline
            $0.filesClient.flushDownloadConnections = {}
            $0.filesClient.browse = { _, path in
                guard path == "A" else { throw FilesClientError.server(statusCode: 404) }
                return listing([file("a.txt", path: "A"), folder("Gone", path: "A")], path: path)
            }
        }
        store.exhaustivity = .off

        await store.send(.resyncTapped)
        await store.receive(\.waitingForNetwork)

        #expect(slots.value == ["A/a.txt", "A/Gone/b.txt"], "a partial walk never prunes")
        #expect(offline.pinnedRoots().map(\.path) == ["A"])
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

    // MARK: Account scope

    private final class ScopeBox: @unchecked Sendable {
        private let lock = NSLock()
        private var scope: String

        init(_ scope: String) {
            self.scope = scope
        }

        var value: String {
            get { lock.withLock { scope } }
            set { lock.withLock { scope = newValue } }
        }
    }

    private enum ScopeFixture {
        static let accountA = "https://files.example.com|alice"
        static let accountB = "https://files.example.com|bob"
    }

    /// A store whose every call records the scope it ran under.
    private func recordingStore(
        seen: LockIsolated<Set<String>>, base: OfflineFileStore
    ) -> OfflineFileStore {
        var store = base
        store.pinnedRoots = { seen.withValue { $0.insert(CacheAccountScope.current) }; return base.pinnedRoots() }
        store.setPinnedRoots = { roots in seen.withValue { $0.insert(CacheAccountScope.current) }; base.setPinnedRoots(roots) }
        store.reconcile = { paths in seen.withValue { $0.insert(CacheAccountScope.current) }; base.reconcile(paths) }
        store.localURL = { item in seen.withValue { $0.insert(CacheAccountScope.current) }; return base.localURL(item) }
        store.setInterrupted = { value in seen.withValue { $0.insert(CacheAccountScope.current) }; base.setInterrupted(value) }
        store.wasInterrupted = { seen.withValue { $0.insert(CacheAccountScope.current) }; return base.wasInterrupted() }
        store.lastAutoSyncAt = { seen.withValue { $0.insert(CacheAccountScope.current) }; return base.lastAutoSyncAt() }
        store.setLastAutoSyncAt = { date in seen.withValue { $0.insert(CacheAccountScope.current) }; base.setLastAutoSyncAt(date) }
        return store
    }

    private func scopedState(_ box: ScopeBox) -> OfflineDownloadsFeature.State {
        withDependencies {
            $0.cacheScope = CacheScopeSource(current: { box.value })
        } operation: {
            OfflineDownloadsFeature.State(serverURL: serverURL)
        }
    }

    @Test
    func aSyncStartedForOneAccountKeepsUsingItAfterTheActiveAccountChanges() async {
        let box = ScopeBox(ScopeFixture.accountA)
        let seen = LockIsolated<Set<String>>([])
        let base = pinnedStore(["A"])
        let store = TestStore(initialState: scopedState(box)) {
            OfflineDownloadsFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.cacheScope = CacheScopeSource(current: { box.value })
            $0.offlineFileStore = recordingStore(seen: seen, base: base)
            $0.filesClient.flushDownloadConnections = {}
            $0.filesClient.browse = { _, path in
                seen.withValue { $0.insert(CacheAccountScope.current) }
                return listing([file("a.txt", path: "A")], path: path)
            }
            $0.filesClient.offlineDownloadFile = { _, _, _ in
                seen.withValue { $0.insert(CacheAccountScope.current) }
                return URL(fileURLWithPath: "/tmp/a.txt")
            }
        }
        store.exhaustivity = .off
        box.value = ScopeFixture.accountB

        await store.send(.resyncTapped)
        await store.receive(\.completed)

        #expect(seen.value == [ScopeFixture.accountA])
    }

    @Test
    func aDownloadStartedForOneAccountKeepsUsingItAfterTheActiveAccountChanges() async {
        let box = ScopeBox(ScopeFixture.accountA)
        let seen = LockIsolated<Set<String>>([])
        let store = TestStore(initialState: scopedState(box)) {
            OfflineDownloadsFeature()
        } withDependencies: {
            $0.cacheScope = CacheScopeSource(current: { box.value })
            $0.offlineFileStore = recordingStore(seen: seen, base: .inMemory())
            $0.filesClient.flushDownloadConnections = {}
            $0.filesClient.browse = { _, path in
                seen.withValue { $0.insert(CacheAccountScope.current) }
                return listing([file("a.txt", path: "A")], path: path)
            }
            $0.filesClient.offlineDownloadFile = { _, _, _ in
                seen.withValue { $0.insert(CacheAccountScope.current) }
                return URL(fileURLWithPath: "/tmp/a.txt")
            }
        }
        store.exhaustivity = .off
        box.value = ScopeFixture.accountB

        await store.send(.startDownload([folder("A")]))
        await store.receive(\.completed)

        #expect(seen.value == [ScopeFixture.accountA])
    }

    // MARK: Leaving an account

    private struct HangingSync {
        let store: TestStoreOf<OfflineDownloadsFeature>
        let started: AsyncStream<Void>
        let gate: AsyncStream<Void>.Continuation
        let wasCancelled: LockIsolated<Bool>
    }

    private func hangingSync(box: ScopeBox) -> HangingSync {
        let (started, startedContinuation) = AsyncStream<Void>.makeStream()
        let (gateStream, gate) = AsyncStream<Void>.makeStream()
        let wasCancelled = LockIsolated(false)
        let store = TestStore(initialState: scopedState(box)) {
            OfflineDownloadsFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.offlineFileStore = pinnedStore(["A"])
            $0.filesClient.flushDownloadConnections = {}
            $0.filesClient.browse = { _, path in
                startedContinuation.yield()
                for await _ in gateStream {
                    break
                }
                if Task.isCancelled {
                    wasCancelled.setValue(true)
                    throw CancellationError()
                }
                return BrowseResult(items: [], access: access(), path: path)
            }
        }
        store.exhaustivity = .off
        return HangingSync(store: store, started: started, gate: gate, wasCancelled: wasCancelled)
    }

    @Test
    func leavingAnAccountCancelsItsRunningSyncAndClearsItsProgress() async {
        let box = ScopeBox(ScopeFixture.accountA)
        let hanging = hangingSync(box: box)

        await hanging.store.send(.resyncTapped)
        var started = hanging.started.makeAsyncIterator()
        _ = await started.next()
        #expect(hanging.store.state.progress.phase == .preparing)

        await hanging.store.send(.accountDeactivated(scope: ScopeFixture.accountA))
        await hanging.store.finish()

        #expect(hanging.wasCancelled.value)
        #expect(hanging.store.state.progress.phase == .idle)
    }

    @Test
    func leavingAnotherAccountLeavesThisAccountsSyncRunning() async {
        let box = ScopeBox(ScopeFixture.accountB)
        let hanging = hangingSync(box: box)

        await hanging.store.send(.resyncTapped)
        var started = hanging.started.makeAsyncIterator()
        _ = await started.next()
        await hanging.store.send(.accountDeactivated(scope: ScopeFixture.accountA))
        hanging.gate.yield()
        await hanging.store.finish()

        #expect(!hanging.wasCancelled.value)
    }

    // MARK: Waiting for network

    @Test
    func aSyncStartingOnceBackOnlineClearsTheWaitingNote() async {
        let store = TestStore(initialState: OfflineDownloadsFeature.State(serverURL: serverURL)) {
            OfflineDownloadsFeature()
        } withDependencies: {
            $0.offlineFileStore = .inMemory()
        }
        store.exhaustivity = .off
        store.state.$progress.withLock { $0.phase = .waitingForNetwork }

        await store.send(.autoSync(force: true))

        #expect(store.state.progress.phase == .idle)
    }

    @Test
    func theWaitingNoteIsNotAnActiveRunSoPinsStayVisible() async {
        let store = TestStore(initialState: OfflineDownloadsFeature.State(serverURL: serverURL)) {
            OfflineDownloadsFeature()
        } withDependencies: {
            $0.connectivity = ConnectivityClient(isOnline: { false }, events: { AsyncStream { _ in } })
            $0.offlineFileStore = pinnedStore(["A"])
        }
        store.exhaustivity = .off

        await store.send(.resyncTapped)

        #expect(store.state.progress.phase == .waitingForNetwork)
        #expect(!store.state.progress.isActive)
        #expect(store.state.progress.fractionComplete == 0)
    }
}
