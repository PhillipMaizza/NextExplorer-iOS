import ComposableArchitecture
import FilesClient
@testable import FilesFeature
import Foundation
import Testing
import TestUtils

@Suite(.isolatedDependencies)
@MainActor
struct OfflineManageFeatureTests {
    private let docs = OfflinePinnedRoot(path: "Docs", isDirectory: true)
    private let photo = OfflinePinnedRoot(path: "a.jpg", isDirectory: false)

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
                OfflinePinnedRootUsage(root: OfflinePinnedRoot(path: "Docs", isDirectory: true), sizeBytes: 100),
                OfflinePinnedRootUsage(root: OfflinePinnedRoot(path: "a.jpg", isDirectory: false), sizeBytes: 50),
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

    @Test
    func removeUnpinsTheRootAndNotifies() async {
        let offline = offlineStore()
        var state = OfflineManageFeature.State()
        state.usages = IdentifiedArray(uniqueElements: usages())
        let store = TestStore(initialState: state) {
            OfflineManageFeature()
        } withDependencies: {
            $0.offlineFileStore = offline
        }

        await store.send(.removeTapped(path: "Docs")) {
            $0.usages.remove(id: "Docs")
        }
        await store.receive(.delegate(.changed))
        await store.finish()

        #expect(offline.pinnedRoots() == [OfflinePinnedRoot(path: "a.jpg", isDirectory: false)])
        #expect(store.state.totalBytes == 50)
    }
}
