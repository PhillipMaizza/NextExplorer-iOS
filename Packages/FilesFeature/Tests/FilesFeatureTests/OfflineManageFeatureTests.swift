import ComposableArchitecture
import FilesClient
@testable import FilesFeature
import Foundation
import Testing

@MainActor
struct OfflineManageFeatureTests {
    @Test
    func onAppearLoadsThePinnedRoots() async {
        let offline = OfflineFileStore.inMemory()
        offline.setPinnedRoots([
            OfflinePinnedRoot(path: "Docs", isDirectory: true),
            OfflinePinnedRoot(path: "a.jpg", isDirectory: false),
        ])
        let store = TestStore(initialState: OfflineManageFeature.State()) {
            OfflineManageFeature()
        } withDependencies: {
            $0.offlineFileStore = offline
        }
        store.exhaustivity = .off

        await store.send(.onAppear)
        await store.receive(\.usagesLoaded)
        #expect(store.state.usages.count == 2)
    }

    @Test
    func removeUnpinsTheRootAndNotifies() async {
        let offline = OfflineFileStore.inMemory()
        offline.setPinnedRoots([
            OfflinePinnedRoot(path: "Docs", isDirectory: true),
            OfflinePinnedRoot(path: "a.jpg", isDirectory: false),
        ])
        var state = OfflineManageFeature.State()
        state.usages = [
            OfflinePinnedRootUsage(root: OfflinePinnedRoot(path: "Docs", isDirectory: true), sizeBytes: 100),
            OfflinePinnedRootUsage(root: OfflinePinnedRoot(path: "a.jpg", isDirectory: false), sizeBytes: 50),
        ]
        let store = TestStore(initialState: state) {
            OfflineManageFeature()
        } withDependencies: {
            $0.offlineFileStore = offline
        }
        store.exhaustivity = .off

        await store.send(.removeTapped(path: "Docs"))
        await store.receive(.delegate(.changed))
        #expect(store.state.usages.ids.contains("Docs") == false)
        #expect(store.state.usages.count == 1)
    }
}
