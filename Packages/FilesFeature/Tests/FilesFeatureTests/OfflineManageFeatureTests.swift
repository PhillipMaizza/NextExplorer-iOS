import ComposableArchitecture
import FilesClient
@testable import FilesFeature
import Foundation
import Testing
import TestUtils

@Suite(.isolatedDependencies)
@MainActor
struct OfflineManageFeatureTests {
    private let docs = OfflinePinnedRoot(path: TestFolder.docs, isDirectory: true)
    private let photo = OfflinePinnedRoot(path: TestFile.aPhoto, isDirectory: false)

    private func usages() -> [OfflinePinnedRootUsage] {
        [OfflinePinnedRootUsage(root: docs, sizeBytes: 100), OfflinePinnedRootUsage(root: photo, sizeBytes: 50)]
    }

    private func offlineStore() -> OfflineFileStore {
        let offline = OfflineFileStore.inMemory()
        offline.setPinnedRoots([docs, photo])
        return offline
    }

    @Test
    func onAppearLoadsThePinnedRootsWithTheirSizes() async {
        var offline = offlineStore()
        let seeded = usages()
        offline.pinnedRootUsages = { seeded }
        let store = TestStore(initialState: OfflineManageFeature.State()) {
            OfflineManageFeature()
        } withDependencies: {
            $0.offlineFileStore = offline
        }

        await store.send(.onAppear)
        await store.receive(\.usagesLoaded) {
            $0.usages = [
                OfflinePinnedRootUsage(
                    root: OfflinePinnedRoot(path: TestFolder.docs, isDirectory: true),
                    sizeBytes: 100
                ),
                OfflinePinnedRootUsage(
                    root: OfflinePinnedRoot(path: TestFile.aPhoto, isDirectory: false),
                    sizeBytes: 50
                ),
            ]
        }
        #expect(store.state.totalBytes == 150)
        #expect(store.state.isEmpty == false)
    }

    @Test
    func onAppearWithNothingPinnedLeavesTheListEmpty() async {
        let store = TestStore(initialState: OfflineManageFeature.State()) {
            OfflineManageFeature()
        } withDependencies: {
            $0.offlineFileStore = .inMemory()
        }

        await store.send(.onAppear)
        await store.receive(\.usagesLoaded)
        #expect(store.state.isEmpty)
        #expect(store.state.totalBytes == 0)
    }

    private func loadedStore(offline: OfflineFileStore) -> TestStoreOf<OfflineManageFeature> {
        var state = OfflineManageFeature.State()
        state.usages = IdentifiedArray(uniqueElements: usages())
        return TestStore(initialState: state) {
            OfflineManageFeature()
        } withDependencies: {
            $0.offlineFileStore = offline
        }
    }

    @Test
    func removeAsksFirstAndTouchesNothingUntilConfirmed() async {
        let offline = offlineStore()
        let store = loadedStore(offline: offline)

        await store.send(.removeTapped(path: TestFolder.docs)) {
            $0.removal = OfflineRemovalRequest(paths: [TestFolder.docs], names: [TestFolder.docs])
        }

        #expect(offline.pinnedRoots().count == 2)
        #expect(store.state.usages.count == 2)
    }

    @Test
    func confirmingTheRemovalUnpinsTheRootAndNotifies() async {
        let offline = offlineStore()
        let store = loadedStore(offline: offline)

        await store.send(.removeTapped(path: TestFolder.docs)) {
            $0.removal = OfflineRemovalRequest(paths: [TestFolder.docs], names: [TestFolder.docs])
        }
        await store.send(.removeConfirmed) {
            $0.removal = nil
            $0.usages.remove(id: TestFolder.docs)
        }
        await store.receive(.delegate(.changed))
        await store.finish()

        #expect(offline.pinnedRoots() == [OfflinePinnedRoot(path: TestFile.aPhoto, isDirectory: false)])
        #expect(store.state.totalBytes == 50)
    }

    @Test
    func cancellingTheRemovalKeepsEverything() async {
        let offline = offlineStore()
        let store = loadedStore(offline: offline)

        await store.send(.removeTapped(path: TestFolder.docs)) {
            $0.removal = OfflineRemovalRequest(paths: [TestFolder.docs], names: [TestFolder.docs])
        }
        await store.send(.removeCancelled) { $0.removal = nil }

        #expect(offline.pinnedRoots().count == 2)
        #expect(store.state.usages.count == 2)
    }

    @Test
    func removingSeveralRowsAsksOnceForAllOfThem() async {
        let offline = offlineStore()
        let store = loadedStore(offline: offline)
        let paths = [TestFolder.docs, TestFile.aPhoto]

        await store.send(.removeSelectionTapped(paths: paths)) {
            $0.removal = OfflineRemovalRequest(paths: paths, names: [TestFolder.docs, TestFile.aPhoto])
        }
        await store.send(.removeConfirmed) {
            $0.removal = nil
            $0.usages = []
        }
        await store.receive(.delegate(.changed))
        await store.finish()

        #expect(offline.pinnedRoots().isEmpty)
    }

    @Test
    func removingAPathThatIsNotListedAsksNothing() async {
        let store = loadedStore(offline: offlineStore())

        await store.send(.removeTapped(path: "Elsewhere"))
        await store.send(.removeConfirmed)
    }
}
