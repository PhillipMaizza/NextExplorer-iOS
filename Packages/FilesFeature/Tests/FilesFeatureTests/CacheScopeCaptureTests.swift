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
        static let accountA = "https://files.example.com|alice"
        static let accountB = "https://files.example.com|bob"
        static let server = URL(fileURLWithPath: "/")
        static let timestamp = MockDate.date
        static let path = TestFolder.docs
    }

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

    private func scopeSource(_ box: ScopeBox) -> CacheScopeSource {
        CacheScopeSource(current: { box.value })
    }

    private func favorite() -> Favorite {
        Favorite(
            id: "f1", path: Fixture.path, label: nil, icon: "folder", color: nil, position: 0,
            createdAt: Fixture.timestamp, updatedAt: Fixture.timestamp
        )
    }

    @Test
    func aFavoritesResponseAfterAnAccountSwitchIsSavedUnderTheAccountThatAsked() async {
        let box = ScopeBox(Fixture.accountA)
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

        box.value = Fixture.accountB
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
        let box = ScopeBox(Fixture.accountA)
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

        box.value = Fixture.accountB
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
        let box = ScopeBox(Fixture.accountA)
        let directoryStore = DirectoryCacheStore.inMemory()
        var state = withDependencies { $0.cacheScope = scopeSource(box) } operation: {
            BrowseFeature.State(serverURL: Fixture.server, directoryPath: Fixture.path, title: Fixture.path)
        }
        state.access = FileAccess(canRead: true, canWrite: true, canUpload: true, canDelete: true, canShare: true, canDownload: true)

        box.value = Fixture.accountB
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
