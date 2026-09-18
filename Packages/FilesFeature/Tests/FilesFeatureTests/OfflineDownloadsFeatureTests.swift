import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Testing

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
            $0.filesClient.offlineDownloadFile = { _, item in
                downloaded.withValue { $0.append(item.id) }
                return URL(fileURLWithPath: "/tmp/\(item.name)")
            }
        }
        store.exhaustivity = .off

        await store.send(.startDownload([folder("A")]))
        await store.receive(\.completed)

        #expect(store.state.progress.phase == .completed)
        #expect(store.state.progress.filesTotal == 2)
        #expect(store.state.progress.bytesTotal == 30)
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
            $0.filesClient.browse = { _, path in
                path == "A"
                    ? BrowseResult(items: [file("a.txt", path: "A", size: 5)], access: access(), path: path)
                    : BrowseResult(items: [], access: access(), path: path)
            }
            $0.filesClient.offlineDownloadFile = { _, item in
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
            $0.filesClient.browse = { _, path in
                path == "A"
                    ? BrowseResult(items: [file("old.txt", path: "A"), file("new.txt", path: "A")], access: access(), path: path)
                    : BrowseResult(items: [], access: access(), path: path)
            }
            $0.filesClient.offlineDownloadFile = { _, item in
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
            $0.filesClient.browse = { _, path in
                path == "A"
                    ? BrowseResult(items: [file("new.txt", path: "A")], access: access(), path: path)
                    : BrowseResult(items: [], access: access(), path: path)
            }
            $0.filesClient.offlineDownloadFile = { _, item in
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
            $0.filesClient.browse = { _, _ in BrowseResult(items: [file("a.txt", path: "A")], access: access(), path: "A") }
            $0.filesClient.offlineDownloadFile = { _, _ in URL(fileURLWithPath: "/tmp/a.txt") }
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
            $0.filesClient.offlineDownloadFile = { _, item in
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
}
