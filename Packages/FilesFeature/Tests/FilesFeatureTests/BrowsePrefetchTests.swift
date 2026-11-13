import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import NetworkClient
import Testing
import TestUtils

/// Warming the offline cache for the folders around the one on screen: what is picked, in which
/// order, and on which budget. The warming runs side by side, so the tests compare sets.
@Suite(.isolatedDependencies)
@MainActor
struct BrowsePrefetchTests {
    private let access = BrowseTestSupport.fullAccess

    struct FreshnessCase: Sendable, CustomTestStringConvertible {
        let freshCount: Int
        let warmed: ClosedRange<Int>
        var testDescription: String {
            "\(freshCount) fresh folders"
        }
    }

    private nonisolated static let freshnessCases = [
        FreshnessCase(freshCount: 20, warmed: 20 ... 29),
        FreshnessCase(freshCount: 3, warmed: 3 ... 22),
    ]

    private func folders(_ count: Int) -> [FileItem] {
        (0 ..< count).map { BrowseFixtures.folder(String(format: "F%02d", $0), in: TestPath.docsLowercase) }
    }

    private func path(_ index: Int) -> String {
        String(format: "docs/F%02d", index)
    }

    /// Loads `directories` into `docs` and returns the folders the prefetch asked the server for.
    private func prefetchRun(
        directories: [FileItem],
        favoritePaths: Set<String> = [],
        pinned: [String] = [],
        isMetered: Bool = false,
        freshPaths: Set<String> = [],
        cacheAges: [String: TimeInterval] = [:],
        capturedScope: String? = nil,
        directoryCacheStore: DirectoryCacheStore? = nil
    ) async -> [String] {
        let prefetched = LockIsolated<[String]>([])
        var state = withDependencies {
            if let capturedScope {
                $0.cacheScope = CacheScopeSource(current: { capturedScope })
            }
        } operation: {
            BrowseFixtures.state(TestPath.docsLowercase, title: TestFolder.docs)
        }
        state.favoritePaths = favoritePaths
        let offline = OfflineFileStore.inMemory()
        offline.setPinnedRoots(pinned.map { OfflinePinnedRoot(path: $0, isDirectory: true) })
        let store = BrowseFixtures.store(state) {
            $0.connectivity = ConnectivityClient(
                isOnline: { true },
                events: { AsyncStream { _ in } },
                isMetered: { isMetered }
            )
            $0.offlineFileStore = offline
            $0.date = .constant(MockDate.date)
            $0.filesClient.prefetchDirectory = { _, path in prefetched.withValue { $0.append(path) } }
            if let directoryCacheStore {
                $0.directoryCacheStore = directoryCacheStore
            } else {
                $0.directoryCacheStore.lastWrittenAt = { _, path in
                    if let age = cacheAges[path] {
                        return MockDate.date.addingTimeInterval(-age)
                    }
                    return freshPaths.contains(path) ? Date.distantFuture : Date.distantPast
                }
            }
        }

        await store.send(.itemsResponse(.success(BrowseResult(
            items: directories,
            access: access,
            path: TestPath.docsLowercase
        )))) {
            $0.phase = .loaded
            $0.items = IdentifiedArray(uniqueElements: directories)
            $0.access = access
        }
        let availableOffline = Set(directories.map(\.id).filter(pinned.contains))
        if availableOffline.isEmpty {
            await store.receive(\.offlineAvailabilityComputed)
        } else {
            await store.receive(\.offlineAvailabilityComputed) {
                $0.offlineItemIDs = availableOffline
                $0.offlinePinnedItemIDs = availableOffline
            }
        }
        await store.finish()
        return prefetched.value
    }

    // MARK: Subfolders

    @Test("A folder is warmed again exactly when its cache is as old as the freshness window")
    func theFreshnessWindowBoundaryIsExact() async {
        let window = DirectoryPrefetch.freshnessWindow
        let directories = folders(3)
        let warmed = await prefetchRun(
            directories: directories,
            cacheAges: [path(0): window - 1, path(1): window, path(2): window + 1]
        )
        #expect(Set(warmed) == [path(1), path(2)])
    }

    @Test("The prefetch is capped and takes the nearest folders first")
    func prefetchIsCappedAndTakesTheNearestFoldersFirst() async {
        let prefetched = await prefetchRun(directories: folders(35))

        #expect(prefetched.count == 20)
        #expect(Set(prefetched) == Set((0 ... 19).map(path)))
    }

    @Test("Favorited and pinned folders are warmed ahead of the cap")
    func prefetchPrefersFavoritedAndPinnedFoldersOverTheCap() async {
        let prefetched = await prefetchRun(
            directories: folders(35), favoritePaths: [path(33)], pinned: [path(34)]
        )

        #expect(prefetched.count == 20)
        #expect(Set(prefetched) == Set((0 ... 17).map(path) + [path(33), path(34)]))
    }

    @Test("The preferred folders go first and the listing order holds within each group")
    func prefetchOrderKeepsListingOrderWithinEachGroup() {
        let order = BrowseFeature.prefetchOrder(["a", "b", "c", "d"], preferred: ["d", "b"])
        #expect(order == ["b", "d", "a", "c"])
    }

    @Test("Nothing is warmed on a metered connection")
    func prefetchIsSkippedOnAMeteredConnection() async {
        let prefetched = await prefetchRun(directories: folders(5), isMetered: true)
        #expect(prefetched.isEmpty)
    }

    @Test(
        "Folders cached recently never spend the budget, which then applies to the stale ones only",
        arguments: freshnessCases
    )
    func theCapAppliesToStaleFoldersOnly(_ testCase: FreshnessCase) async {
        let all = folders(30)
        let fresh = Set((0 ..< testCase.freshCount).map(path))

        let prefetched = await prefetchRun(directories: all, freshPaths: fresh)

        #expect(Set(prefetched) == Set(testCase.warmed.map(path)))
        #expect(prefetched.count == testCase.warmed.count)
    }

    @Test("The freshness check reads the scope the state captured, not another account's")
    func theFreshnessCheckReadsTheScopeTheStateCapturedNotAnotherAccounts() async {
        let store = DirectoryCacheStore.inMemory()
        let listing = BrowseResult(items: [], access: access, path: TestPath.docsLowercase)
        store.bound(to: "scope-alice").write(
            serverURL: BrowseTestSupport.serverURL,
            path: path(0),
            result: listing,
            etag: nil,
            fetchedAt: Date.distantFuture
        )
        store.bound(to: "scope-bob").write(
            serverURL: BrowseTestSupport.serverURL,
            path: path(1),
            result: listing,
            etag: nil,
            fetchedAt: Date.distantFuture
        )

        let prefetched = await prefetchRun(
            directories: folders(2),
            capturedScope: "scope-alice",
            directoryCacheStore: store
        )

        #expect(prefetched == [path(1)])
    }

    @Test("A listing with no folders never reads the pinned roots")
    func aSuccessfulBrowseOfAnEmptyFolderNeverReadsThePinnedRoots() async {
        let calls = LockIsolated(0)
        let store = BrowseFixtures.store(BrowseFixtures.state(TestPath.docsLowercase, title: TestFolder.docs)) {
            $0.offlineFileStore.pinnedRoots = {
                calls.withValue { $0 += 1 }
                return []
            }
        }

        await store.send(.itemsResponse(.success(BrowseResult(
            items: [],
            access: access,
            path: TestPath.docsLowercase
        )))) {
            $0.phase = .loaded
            $0.access = access
        }
        await store.finish()

        #expect(calls.value == 0)
    }

    // MARK: Favorites

    @Test("Favorites beyond the subfolder cap are still warmed, on their own budget")
    func favoritesBeyondTheSubfolderCapAreStillWarmedOnTheirOwnBudget() async {
        let prefetched = LockIsolated<[String]>([])
        let paths = (0 ..< 45).map { "Fav\($0)" }
        let store = BrowseFixtures.store {
            $0.filesClient.prefetchDirectory = { _, path in prefetched.withValue { $0.append(path) } }
            $0.directoryCacheStore.lastWrittenAt = { _, _ in nil }
        }

        await store.send(.favoritesResponse(paths.map { BrowseFixtures.favorite($0) })) {
            $0.favoritePaths = Set(paths)
            $0.hasLoadedFavorites = true
        }
        await store.finish()

        #expect(prefetched.value.count == 40)
        #expect(Set(prefetched.value) == Set(paths.prefix(40)))
    }

    @Test("A favorite the listing shows as a file is dropped, a known folder or an unknown kind is kept")
    func favoriteFolderPathsKeepsUnknownKindsAndDropsKnownFiles() {
        let known = IdentifiedArray(uniqueElements: [
            BrowseFixtures.file(TestFile.aText, in: TestPath.docsLowercase), BrowseFixtures.folder(
                "Known",
                in: TestPath.docsLowercase
            ),
        ])

        let paths = BrowseFeature.favoriteFolderPaths(
            [
                BrowseFixtures.favorite("docs/a.txt"), BrowseFixtures.favorite("docs/Known", position: 1),
                BrowseFixtures.favorite("Unknown", position: 2),
            ],
            knownItems: known
        )

        #expect(paths == ["docs/Known", "Unknown"])
    }
}
