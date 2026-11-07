import ComposableArchitecture
import CoreModels
import DependenciesTestSupport
import FilesClient
@testable import FilesFeature
import Foundation
import Testing

@Suite(.dependencies)
@MainActor
struct BrowseReviewFixTests {
    private let serverURL = URL(string: "https://example.com") ?? URL(fileURLWithPath: "/")

    private nonisolated static let access = FileAccess(
        canRead: true, canWrite: true, canUpload: true, canDelete: true, canShare: true, canDownload: true
    )

    private nonisolated func folder(_ name: String, path: String = "docs") -> FileItem {
        FileItem(name: name, path: path, dateModified: MockDates.reference, size: 0, kind: "directory")
    }

    private nonisolated func file(_ name: String, path: String = "docs") -> FileItem {
        FileItem(name: name, path: path, dateModified: MockDates.reference, size: 1, kind: "txt")
    }

    private nonisolated func favorite(_ path: String) -> Favorite {
        Favorite(id: path, path: path, label: nil, icon: "folder", color: nil, position: 0, createdAt: MockDates.reference, updatedAt: MockDates.reference)
    }

    private func cachedDirectoryStore(_ items: [FileItem]) -> @Sendable (URL, String) -> CachedDirectory? {
        { _, _ in CachedDirectory(path: "docs", items: items, access: Self.access, fetchedAt: MockDates.reference) }
    }

    // MARK: Cache paint then a real server error

    @Test(arguments: [404, 403, 500])
    func aServerErrorAfterTheCachePaintShowsTheErrorNotTheStaleList(statusCode: Int) async {
        let cached = file("Stale.txt")
        let gate = AsyncStream<Void>.makeStream()
        let store = TestStore(initialState: BrowseFeature.State(serverURL: serverURL, directoryPath: "docs", title: "Docs")) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.browse = { _, _ in
                for await _ in gate.stream {
                    break
                }
                throw FilesClientError.server(statusCode: statusCode)
            }
            $0.filesClient.favorites = { _ in [] }
            $0.directoryCacheStore.read = cachedDirectoryStore([cached])
        }
        store.exhaustivity = .off

        await store.send(.onAppear)
        await store.receive(\.cachedListingPainted)
        #expect(store.state.items.count == 1)
        gate.continuation.yield(())
        await store.receive(\.itemsResponse.failure)

        #expect(store.state.items.isEmpty)
        #expect(store.state.phase == .failed(FilesClientError.server(statusCode: statusCode).userMessage))
        #expect(store.state.dataSource == .live)
        #expect(!store.state.isShowingCachePaint)
    }

    @Test
    func anOfflineErrorAfterTheCachePaintStillShowsTheSavedCopy() async {
        let cached = file("Saved.txt")
        let gate = AsyncStream<Void>.makeStream()
        let store = TestStore(initialState: BrowseFeature.State(serverURL: serverURL, directoryPath: "docs", title: "Docs")) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.browse = { _, _ in
                for await _ in gate.stream {
                    break
                }
                throw FilesClientError.offline
            }
            $0.filesClient.favorites = { _ in [] }
            $0.directoryCacheStore.read = cachedDirectoryStore([cached])
        }
        store.exhaustivity = .off

        await store.send(.onAppear)
        await store.receive(\.cachedListingPainted)
        gate.continuation.yield(())
        await store.receive(\.itemsResponse.failure)
        await store.receive(\.offlineListingResolved)

        #expect(store.state.items.count == 1)
        #expect(store.state.dataSource == .cached(fetchedAt: MockDates.reference))
        #expect(!store.state.isShowingCachePaint)
    }

    @Test
    func aServerErrorOnARefreshOfALiveLoadedFolderKeepsTheListWithAToast() async {
        var state = BrowseFeature.State(serverURL: serverURL, directoryPath: "docs", title: "Docs")
        state.items = [file("Live.txt")]
        state.access = Self.access
        state.phase = .loaded
        let store = TestStore(initialState: state) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.browse = { _, _ in throw FilesClientError.server(statusCode: 500) }
            $0.filesClient.favorites = { _ in [] }
            $0.directoryCacheStore.read = { _, _ in nil }
        }
        store.exhaustivity = .off

        await store.send(.refreshButtonTapped)
        await store.receive(\.itemsResponse.failure)

        #expect(store.state.items.count == 1)
        #expect(store.state.phase == .loaded)
        #expect(store.state.dataSource == .live)
        #expect(store.state.fileActionErrorMessage == FilesClientError.server(statusCode: 500).userMessage)
    }

    @Test
    func aServerErrorOnARefreshOfAnOfflineSavedCopyShowsTheErrorNotTheStaleList() async {
        var state = BrowseFeature.State(serverURL: serverURL, directoryPath: "docs", title: "Docs")
        state.items = [file("Saved.txt")]
        state.access = Self.access
        state.phase = .loaded
        state.dataSource = .cached(fetchedAt: MockDates.reference)
        let store = TestStore(initialState: state) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.browse = { _, _ in throw FilesClientError.server(statusCode: 404) }
            $0.filesClient.favorites = { _ in [] }
            $0.directoryCacheStore.read = { _, _ in nil }
        }
        store.exhaustivity = .off

        await store.send(.refreshButtonTapped)
        await store.receive(\.itemsResponse.failure)

        #expect(store.state.items.isEmpty)
        #expect(store.state.phase == .failed(FilesClientError.server(statusCode: 404).userMessage))
        #expect(store.state.dataSource == .live)
    }

    // MARK: Pinned roots stay off the reducer

    @Test
    func aSuccessfulBrowseOfAnEmptyFolderNeverReadsThePinnedRoots() async {
        let calls = LockIsolated(0)
        let store = TestStore(initialState: BrowseFeature.State(serverURL: serverURL, directoryPath: "docs", title: "Docs")) {
            BrowseFeature()
        } withDependencies: {
            $0.offlineFileStore.pinnedRoots = {
                calls.withValue { $0 += 1 }
                return []
            }
        }
        store.exhaustivity = .off

        await store.send(.itemsResponse(.success(BrowseResult(items: [], access: Self.access, path: "docs"))))
        await store.finish()

        #expect(calls.value == 0)
    }

    @Test
    func aSuccessfulBrowseWithFoldersReadsThePinnedRootsForThePrefetch() async {
        let calls = LockIsolated(0)
        let store = TestStore(initialState: BrowseFeature.State(serverURL: serverURL, directoryPath: "docs", title: "Docs")) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.prefetchDirectory = { _, _ in }
            $0.directoryCacheStore.lastWrittenAt = { _, _ in nil }
            $0.offlineFileStore.pinnedRoots = {
                calls.withValue { $0 += 1 }
                return []
            }
        }
        store.exhaustivity = .off

        await store.send(.itemsResponse(.success(BrowseResult(items: [folder("Photos")], access: Self.access, path: "docs"))))
        await store.finish()

        #expect(calls.value > 0)
    }

    // MARK: Prefetch budgets

    @Test
    func favoritesBeyondTheSubfolderCapAreStillWarmedOnTheirOwnBudget() async {
        let prefetched = LockIsolated<[String]>([])
        let paths = (0 ..< 45).map { "Fav\($0)" }
        let store = TestStore(initialState: BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Browse")) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.prefetchDirectory = { _, path in prefetched.withValue { $0.append(path) } }
            $0.directoryCacheStore.lastWrittenAt = { _, _ in nil }
        }
        store.exhaustivity = .off

        await store.send(.favoritesResponse(paths.map(favorite)))
        await store.finish()

        #expect(prefetched.value.count == BrowseFeature.Constants.maxPrefetchedFavorites)
        #expect(BrowseFeature.Constants.maxPrefetchedFavorites > BrowseFeature.Constants.maxPrefetchedFolders)
        #expect(Set(prefetched.value) == Set(paths.prefix(BrowseFeature.Constants.maxPrefetchedFavorites)))
    }

    @Test
    func subfoldersKeepTheirOwnSmallerCap() async {
        let prefetched = LockIsolated<[String]>([])
        let folders = (0 ..< 30).map { folder("Sub\($0)") }
        let store = TestStore(initialState: BrowseFeature.State(serverURL: serverURL, directoryPath: "docs", title: "Docs")) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.browse = { _, _ in BrowseResult(items: folders, access: Self.access, path: "docs") }
            $0.filesClient.favorites = { _ in [] }
            $0.filesClient.prefetchDirectory = { _, path in prefetched.withValue { $0.append(path) } }
            $0.directoryCacheStore.read = { _, _ in nil }
            $0.directoryCacheStore.lastWrittenAt = { _, _ in nil }
        }
        store.exhaustivity = .off

        await store.send(.onAppear)
        await store.receive(\.itemsResponse.success)
        await store.finish()

        #expect(prefetched.value.count == BrowseFeature.Constants.maxPrefetchedFolders)
    }
}

enum MockDates {
    static let reference = Date(timeIntervalSince1970: 1_000)
}
