import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Testing
import TestUtils

/// A late response after an account switch must land in the account that asked for it. The scope
/// source is injected and flipped between creating a feature and its response; the process wide
/// `CacheAccountScope` is never touched.
@Suite(.isolatedDependencies)
@MainActor
struct CacheScopeCaptureTests {
    private enum Fixture {
        static let accountA = TestAccountID.alice
        static let accountB = TestAccountID.bob
        static let server = URL(fileURLWithPath: "/")
        static let timestamp = MockDate.date
        static let path = TestFolder.docs
    }

    private func scopeSource(_ box: LockIsolated<String>) -> CacheScopeSource {
        CacheScopeSource(current: { box.value })
    }

    private func favorite() -> Favorite {
        Favorite(
            id: "f1", path: Fixture.path, label: nil, icon: "folder", color: nil, position: 0,
            createdAt: Fixture.timestamp, updatedAt: Fixture.timestamp
        )
    }

    @Test
    func preferencesAnsweredAfterAnAccountSwitchNeverReachTheNextAccount() async {
        let box = LockIsolated(Fixture.accountA)
        let answer = AsyncGate()
        let state = SettingsFeature.State(serverURL: Fixture.server, user: User.janeDoeFixture)
        state.$preferences.withLock { $0 = UserPreferences() }
        let store = TestStore(initialState: state) {
            SettingsFeature()
        } withDependencies: {
            $0.cacheScope = scopeSource(box)
            $0.filesClient.fetchPreferences = { _ in
                try await answer.wait()
                return UserPreferences(shouldShowHiddenFiles: true)
            }
        }

        await store.send(.loadPreferences)
        box.setValue(Fixture.accountB)
        answer.open()
        await store.finish()

        #expect(store.state.preferences == UserPreferences())
    }

    @Test
    func aFolderSortSavedAfterAnAccountSwitchNeverReachesTheNextAccount() async {
        let box = LockIsolated(Fixture.accountA)
        let answer = AsyncGate()
        let sort = FolderSort(field: BrowseFeature.SortOption.size.rawValue, isAscending: false)
        let echoed = FolderSort(field: BrowseFeature.SortOption.name.rawValue, isAscending: true)
        let state = withDependencies { $0.cacheScope = scopeSource(box) } operation: {
            BrowseFeature.State(serverURL: Fixture.server, directoryPath: Fixture.path, title: Fixture.path)
        }
        state.$preferences.withLock { $0 = UserPreferences() }
        let store = TestStore(initialState: state) {
            BrowseFeature()
        } withDependencies: {
            $0.cacheScope = scopeSource(box)
            $0.filesClient.saveFolderSort = { _, _, _ in
                try await answer.wait()
                return echoed
            }
        }

        await store.send(.sortChanged(.size, .descending)) {
            $0.$preferences.withLock { $0.setFolderSort(sort, for: Fixture.path) }
        }
        box.setValue(Fixture.accountB)
        answer.open()
        await store.finish()

        #expect(store.state.preferences.folderSort(for: Fixture.path) == sort)
    }

    @Test
    func aFavoritesResponseAfterAnAccountSwitchIsSavedUnderTheAccountThatAsked() async {
        let box = LockIsolated(Fixture.accountA)
        let jsonStore = JSONCacheStore.inMemory()
        let state = withDependencies { $0.cacheScope = scopeSource(box) } operation: {
            FavoritesFeature.State(serverURL: Fixture.server)
        }
        let store = TestStore(initialState: state) {
            FavoritesFeature()
        } withDependencies: {
            $0.jsonCacheStore = jsonStore
            $0.cacheScope = scopeSource(box)
            $0.filesClient.fetchMetadata = { _, _ in throw FilesClientError.offline }
        }

        box.setValue(Fixture.accountB)
        await store.send(.favoritesResponse(.success([favorite()]))) {
            $0.phase = .loaded
            $0.favorites = [favorite()]
        }
        await store.receive(\.offlineAvailabilityComputed)

        let key = ListCache.key(FavoritesFeature.cacheNamespace, serverURL: Fixture.server)
        #expect(jsonStore.bound(to: Fixture.accountA).read(key: key) != nil)
        #expect(jsonStore.bound(to: Fixture.accountB).read(key: key) == nil)
    }

    @Test
    func aSharesResponseAfterAnAccountSwitchIsSavedUnderTheAccountThatAsked() async {
        let box = LockIsolated(Fixture.accountA)
        let jsonStore = JSONCacheStore.inMemory()
        let state = withDependencies { $0.cacheScope = scopeSource(box) } operation: {
            SharedFeature.State(serverURL: Fixture.server)
        }
        let store = TestStore(initialState: state) {
            SharedFeature()
        } withDependencies: {
            $0.jsonCacheStore = jsonStore
            $0.cacheScope = scopeSource(box)
        }

        box.setValue(Fixture.accountB)
        await store.send(.sharesResponse(.byMe, .success([]))) {
            $0.phases[.byMe] = .loaded
            $0.dataSources[.byMe] = .live
        }

        let key = ListCache.key(SharedFeature.cacheNamespace(.byMe), serverURL: Fixture.server)
        #expect(jsonStore.bound(to: Fixture.accountA).read(key: key) != nil)
        #expect(jsonStore.bound(to: Fixture.accountB).read(key: key) == nil)
    }

    @Test
    func aListingSyncAfterAnAccountSwitchIsWrittenUnderTheAccountThatAsked() {
        let box = LockIsolated(Fixture.accountA)
        let directoryStore = DirectoryCacheStore.inMemory()
        var state = withDependencies { $0.cacheScope = scopeSource(box) } operation: {
            BrowseFeature.State(serverURL: Fixture.server, directoryPath: Fixture.path, title: Fixture.path)
        }
        state.access = FileAccess(
            canRead: true,
            canWrite: true,
            canUpload: true,
            canDelete: true,
            canShare: true,
            canDownload: true
        )

        box.setValue(Fixture.accountB)
        withDependencies {
            $0.directoryCacheStore = directoryStore
            $0.date = .constant(Fixture.timestamp)
        } operation: {
            BrowseFeature().syncListingCache(state)
        }

        #expect(directoryStore.bound(to: Fixture.accountA).read(serverURL: Fixture.server, path: Fixture.path) != nil)
        #expect(directoryStore.bound(to: Fixture.accountB).read(serverURL: Fixture.server, path: Fixture.path) == nil)
    }
}
