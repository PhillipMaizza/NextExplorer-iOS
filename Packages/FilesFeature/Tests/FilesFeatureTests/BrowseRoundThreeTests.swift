import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import NetworkClient
import Testing
import TestUtils

@Suite(.isolatedDependencies)
@MainActor
struct BrowseRoundThreeTests {
    private let serverURL = URL(string: "https://example.com") ?? URL(fileURLWithPath: "/")
    private let accountA = "https://example.com|alice"

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

    private func loadedState(items: [FileItem], path: String = "docs") -> BrowseFeature.State {
        var state = BrowseFeature.State(serverURL: serverURL, directoryPath: path, title: "Docs")
        state.items = IdentifiedArray(uniqueElements: items)
        state.access = Self.access
        state.phase = .loaded
        return state
    }

    // MARK: Gateway answers on a mutation

    @Test(arguments: [502, 503, 504, 524])
    func aGatewayAnswerToADeleteRefetchesTheFolder(statusCode: Int) async {
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

        await store.send(.deleteResponse(.failure(.server(statusCode: statusCode))))
        await store.receive(\.itemsResponse.success)
        await store.finish()

        #expect(browseCalls.value == 1)
        #expect(store.state.items.isEmpty)
    }

    @Test
    func aGatewayAnswerCarryingAMessageToATransferRefetchesTheFolder() async {
        let browseCalls = LockIsolated(0)
        let store = TestStore(initialState: loadedState(items: [file("a.txt")])) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.browse = { _, path in
                browseCalls.withValue { $0 += 1 }
                return BrowseResult(items: [file("a.txt")], access: Self.access, path: path)
            }
            $0.filesClient.favorites = { _ in [] }
        }
        store.exhaustivity = .off

        await store.send(.transferResponse(.failure(.serverMessage(statusCode: 504, message: "Gateway Timeout"))))
        await store.receive(\.itemsResponse.success)
        await store.finish()

        #expect(browseCalls.value == 1)
    }

    @Test(arguments: [400, 401, 403, 404, 409, 413, 415, 429, 500, 501])
    func otherServerStatusesDoNotRefetch(statusCode: Int) {
        #expect(!BrowseFeature.mayHaveAppliedOnServer(.server(statusCode: statusCode)))
        #expect(!BrowseFeature.mayHaveAppliedOnServer(.serverMessage(statusCode: statusCode, message: "No")))
    }

    @Test
    func onlyTimeoutsAndGatewayAnswersMayHaveAppliedOnTheServer() {
        #expect(BrowseFeature.mayHaveAppliedOnServer(.timedOut))
        #expect(!BrowseFeature.mayHaveAppliedOnServer(.offline))
        #expect(!BrowseFeature.mayHaveAppliedOnServer(.sessionExpired))
        #expect(!BrowseFeature.mayHaveAppliedOnServer(.rateLimited))
        #expect(!BrowseFeature.mayHaveAppliedOnServer(.changedOnServer))
    }

    // MARK: Favorites before the first answer

    @Test
    func aStarTapBeforeTheFirstFavoritesAnswerDoesNotTouchTheServer() async {
        let adds = LockIsolated(0)
        let removes = LockIsolated(0)
        let store = TestStore(initialState: loadedState(items: [folder("A")])) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.addFavorite = { _, path in
                adds.withValue { $0 += 1 }
                return favorite(path)
            }
            $0.filesClient.removeFavorite = { _, _ in removes.withValue { $0 += 1 } }
        }

        await store.send(.favoriteToggleButtonTapped(folder("A")))
        await store.send(.bulkFavoriteTapped)
        await store.finish()

        #expect(!store.state.hasLoadedFavorites)
        #expect(adds.value == 0)
        #expect(removes.value == 0)
    }

    @Test
    func aFailedFirstFavoritesFetchKeepsStarsDisabledSoAFavoritedFolderIsNotReAdded() async {
        let adds = LockIsolated(0)
        var state = loadedState(items: [folder("A")])
        state.phase = .idle
        let store = TestStore(initialState: state) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.browse = { _, path in BrowseResult(items: [folder("A")], access: Self.access, path: path) }
            $0.filesClient.favorites = { _ in throw FilesClientError.server(statusCode: 500) }
            $0.filesClient.addFavorite = { _, path in
                adds.withValue { $0 += 1 }
                return favorite(path)
            }
            $0.filesClient.prefetchDirectory = { _, _ in }
            $0.directoryCacheStore.lastWrittenAt = { _, _ in nil }
        }
        store.exhaustivity = .off

        await store.send(.onAppear)
        await store.receive(\.itemsResponse.success)
        await store.finish()
        await store.send(.favoriteToggleButtonTapped(folder("A")))
        await store.finish()

        #expect(!store.state.hasLoadedFavorites)
        #expect(adds.value == 0)
    }

    @Test
    func onceFavoritesHaveLoadedAStarTapRemovesAnExistingFavoriteInsteadOfReAddingIt() async {
        let removed = LockIsolated<[String]>([])
        let adds = LockIsolated(0)
        let store = TestStore(initialState: loadedState(items: [folder("A")])) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.removeFavorite = { _, path in removed.withValue { $0.append(path) } }
            $0.filesClient.addFavorite = { _, path in
                adds.withValue { $0 += 1 }
                return favorite(path)
            }
            $0.filesClient.prefetchDirectory = { _, _ in }
            $0.directoryCacheStore.lastWrittenAt = { _, _ in nil }
        }
        store.exhaustivity = .off

        await store.send(.favoritesResponse([favorite("docs/A")]))
        #expect(store.state.hasLoadedFavorites)
        await store.send(.favoriteToggleButtonTapped(folder("A")))
        await store.receive(\.favoriteToggleResponse.success)
        await store.finish()

        #expect(removed.value == ["docs/A"])
        #expect(adds.value == 0)
        #expect(!store.state.favoritePaths.contains("docs/A"))
    }

    @Test
    func anEmptyFavoritesAnswerStillEnablesStars() async {
        let store = TestStore(initialState: loadedState(items: [])) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.prefetchDirectory = { _, _ in }
        }
        store.exhaustivity = .off

        await store.send(.favoritesResponse([]))

        #expect(store.state.hasLoadedFavorites)
    }

    // MARK: Prefetch

    private func prefetchRun(
        directories: [FileItem],
        freshPaths: Set<String> = [],
        capturedScope: String? = nil,
        directoryCacheStore: DirectoryCacheStore? = nil
    ) async -> [String] {
        let prefetched = LockIsolated<[String]>([])
        let state = withDependencies {
            if let capturedScope {
                $0.cacheScope = CacheScopeSource(current: { capturedScope })
            }
        } operation: {
            BrowseFeature.State(serverURL: serverURL, directoryPath: "docs", title: "Docs")
        }
        let store = TestStore(initialState: state) {
            BrowseFeature()
        } withDependencies: {
            $0.connectivity = ConnectivityClient(isOnline: { true }, events: { AsyncStream { _ in } }, isMetered: { false })
            $0.offlineFileStore = OfflineFileStore.inMemory()
            $0.filesClient.prefetchDirectory = { _, path in prefetched.withValue { $0.append(path) } }
            if let directoryCacheStore {
                $0.directoryCacheStore = directoryCacheStore
            } else {
                $0.directoryCacheStore.lastWrittenAt = { _, path in
                    freshPaths.contains(path) ? Date.distantFuture : Date.distantPast
                }
            }
        }
        store.exhaustivity = .off

        await store.send(.itemsResponse(.success(BrowseResult(items: directories, access: Self.access, path: "docs"))))
        await store.finish()
        return prefetched.value
    }

    private func folders(_ count: Int) -> [FileItem] {
        (0 ..< count).map { folder(String(format: "F%02d", $0)) }
    }

    @Test
    func freshFoldersDoNotSpendThePrefetchBudget() async {
        let all = folders(30)
        let fresh = Set(all.prefix(BrowseFeature.Constants.maxPrefetchedFolders).map(\.id))

        let prefetched = await prefetchRun(directories: all, freshPaths: fresh)

        #expect(Set(prefetched) == Set(all.suffix(10).map(\.id)))
    }

    @Test
    func theCapAppliesToStaleFoldersOnly() async {
        let all = folders(30)
        let fresh: Set = ["docs/F00", "docs/F01", "docs/F02"]

        let prefetched = await prefetchRun(directories: all, freshPaths: fresh)

        #expect(prefetched.count == BrowseFeature.Constants.maxPrefetchedFolders)
        #expect(fresh.isDisjoint(with: prefetched))
        #expect(prefetched.contains("docs/F22"))
        #expect(!prefetched.contains("docs/F23"))
    }

    @Test
    func theFreshnessCheckReadsTheScopeTheStateCapturedNotAnotherAccounts() async {
        let all = folders(2)
        let store = DirectoryCacheStore.inMemory()
        let listing = BrowseResult(items: [], access: Self.access, path: "docs")
        store.bound(to: accountA).write(serverURL: serverURL, path: "docs/F00", result: listing, etag: nil, fetchedAt: Date.distantFuture)
        store.bound(to: "https://example.com|bob").write(serverURL: serverURL, path: "docs/F01", result: listing, etag: nil, fetchedAt: Date.distantFuture)

        let prefetched = await prefetchRun(directories: all, capturedScope: accountA, directoryCacheStore: store)

        #expect(prefetched == ["docs/F01"])
    }

    @Test
    func favoritesKnownToBeFilesAreNotPrefetched() async {
        let prefetched = LockIsolated<[String]>([])
        var state = loadedState(items: [file("a.txt"), folder("Known")])
        state.phase = .loaded
        let store = TestStore(initialState: state) {
            BrowseFeature()
        } withDependencies: {
            $0.connectivity = ConnectivityClient(isOnline: { true }, events: { AsyncStream { _ in } }, isMetered: { false })
            $0.filesClient.prefetchDirectory = { _, path in prefetched.withValue { $0.append(path) } }
            $0.directoryCacheStore.lastWrittenAt = { _, _ in nil }
        }
        store.exhaustivity = .off

        await store.send(.favoritesResponse([favorite("docs/a.txt"), favorite("docs/Known"), favorite("Elsewhere")]))
        await store.finish()

        #expect(Set(prefetched.value) == ["docs/Known", "Elsewhere"])
    }

    @Test
    func favoriteFolderPathsKeepsUnknownKindsAndDropsKnownFiles() {
        let known = IdentifiedArray(uniqueElements: [file("a.txt"), folder("Known")])

        let paths = BrowseFeature.favoriteFolderPaths(
            [favorite("docs/a.txt"), favorite("docs/Known"), favorite("Unknown")], knownItems: known
        )

        #expect(paths == ["docs/Known", "Unknown"])
    }

    // MARK: Disk reads run in effects

    @Test
    func anOfflineFailureReadsTheSavedListingInAnEffectAndThenShowsIt() async {
        let cached = file("Saved.txt")
        let store = TestStore(initialState: loadedState(items: [file("Live.txt")])) {
            BrowseFeature()
        } withDependencies: {
            $0.directoryCacheStore.read = { _, _ in
                CachedDirectory(path: "docs", items: [cached], access: Self.access, fetchedAt: MockDates.reference)
            }
        }
        store.exhaustivity = .off

        await store.send(.itemsResponse(.failure(.offline)))
        #expect(store.state.items.map(\.name) == ["Live.txt"])
        await store.receive(\.offlineListingResolved)

        #expect(store.state.items.map(\.name) == ["Saved.txt"])
        #expect(store.state.dataSource == .cached(fetchedAt: MockDates.reference))
        #expect(store.state.phase == .loaded)
    }

    @Test
    func anOfflineFailureWithNothingSavedAndNothingOnScreenIsAnError() async {
        var state = BrowseFeature.State(serverURL: serverURL, directoryPath: "docs", title: "Docs")
        state.phase = .loading
        let store = TestStore(initialState: state) {
            BrowseFeature()
        } withDependencies: {
            $0.directoryCacheStore.read = { _, _ in nil }
        }
        store.exhaustivity = .off

        await store.send(.itemsResponse(.failure(.offline)))
        await store.receive(\.offlineListingResolved)

        #expect(store.state.phase == .failed(FilesClientError.offline.userMessage))
    }

    @Test
    func theFirstLoadPaintsTheSavedListingFromAnEffectBesideTheFetch() async {
        let cached = file("Saved.txt")
        let gate = AsyncStream<Void>.makeStream()
        var state = BrowseFeature.State(serverURL: serverURL, directoryPath: "docs", title: "Docs")
        state.phase = .idle
        let store = TestStore(initialState: state) {
            BrowseFeature()
        } withDependencies: {
            $0.directoryCacheStore.read = { _, _ in
                CachedDirectory(path: "docs", items: [cached], access: Self.access, fetchedAt: MockDates.reference)
            }
            $0.filesClient.browse = { _, path in
                for await _ in gate.stream {
                    break
                }
                return BrowseResult(items: [], access: Self.access, path: path)
            }
            $0.filesClient.favorites = { _ in [] }
            $0.filesClient.prefetchDirectory = { _, _ in }
        }
        store.exhaustivity = .off

        await store.send(.onAppear)
        #expect(store.state.items.isEmpty)
        await store.receive(\.cachedListingPainted)
        #expect(store.state.items.map(\.name) == ["Saved.txt"])
        #expect(store.state.isShowingCachePaint)

        gate.continuation.yield(())
        await store.receive(\.itemsResponse.success)
        await store.finish()
        #expect(store.state.items.isEmpty)
        #expect(!store.state.isShowingCachePaint)
    }

    @Test
    func aPaintThatArrivesAfterTheLiveListingIsDropped() async {
        var state = loadedState(items: [file("Live.txt")])
        state.phase = .loaded
        let store = TestStore(initialState: state) {
            BrowseFeature()
        }

        let stale = CachedDirectory(path: "docs", items: [file("Stale.txt")], access: Self.access, fetchedAt: MockDates.reference)
        await store.send(.cachedListingPainted(stale))

        #expect(store.state.items.map(\.name) == ["Live.txt"])
    }
}
