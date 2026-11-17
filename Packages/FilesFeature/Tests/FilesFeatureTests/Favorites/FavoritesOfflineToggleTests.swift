import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Testing
import TestUtils

/// The Available Offline toggle on a favorite folder.
@Suite(.isolatedDependencies)
@MainActor
struct FavoritesOfflineToggleTests: FavoritesTestSupport {
    private enum Constants {
        static let nestedPath = "Docs/Reports"
        static let nestedName = "Reports"
    }

    private var pinnedFolder: FileItem {
        FileItem(
            name: Constants.nestedName,
            path: TestFolder.docs,
            dateModified: MockDate.date,
            size: 0,
            kind: FileItem.directoryKind
        )
    }

    private func store(_ configure: (inout FavoritesFeature.State) -> Void = { _ in
    }) -> TestStoreOf<FavoritesFeature> {
        var state = FavoritesFeature.State(serverURL: serverURL)
        configure(&state)
        return TestStore(initialState: state) { FavoritesFeature() }
    }

    @Test
    func togglingAFavoriteThatIsNotOfflinePinsItsFolder() async {
        let favorite = makeFavorite(id: "A", path: Constants.nestedPath)
        let store = store()

        await store.send(.offlineToggleTapped(favorite)) {
            $0.offlineFavoriteIDs = ["A"]
            $0.offlinePinnedFavoriteIDs = ["A"]
        }
        await store.receive(.delegate(.offlinePinRequested([pinnedFolder])))
    }

    @Test
    func togglingAPinnedFavoriteAsksThenUnpinsOnConfirm() async {
        let favorite = makeFavorite(id: "A", path: Constants.nestedPath)
        let store = store {
            $0.favorites = [favorite]
            $0.offlineFavoriteIDs = ["A"]
            $0.offlinePinnedFavoriteIDs = ["A"]
        }
        let request = OfflineRemovalRequest(paths: [Constants.nestedPath], names: [favorite.displayName])

        await store.send(.offlineToggleTapped(favorite)) { $0.offlineRemoval = request }
        await store.send(.offlineRemovalCancelled) { $0.offlineRemoval = nil }
        await store.send(.offlineToggleTapped(favorite)) { $0.offlineRemoval = request }
        await store.send(.offlineRemovalConfirmed) {
            $0.offlineRemoval = nil
            $0.offlineFavoriteIDs = []
            $0.offlinePinnedFavoriteIDs = []
        }
        await store.receive(.delegate(.offlineUnpinRequested(path: Constants.nestedPath)))
    }

    @Test("Taking a favorite folder off clears the mark on a favorite inside it, not one pinned on its own")
    func removingAFavoriteClearsTheFavoritesInsideIt() async {
        let docs = makeFavorite(id: "A", path: TestFolder.docs)
        let reports = makeFavorite(id: "B", path: Constants.nestedPath)
        let pinnedReports = makeFavorite(id: "C", path: "\(Constants.nestedPath)/\(Constants.nestedName)")
        let store = store {
            $0.favorites = [docs, reports, pinnedReports]
            $0.offlineFavoriteIDs = ["A", "B", "C"]
            $0.offlinePinnedFavoriteIDs = ["A", "C"]
            $0.offlineRemoval = OfflineRemovalRequest(paths: [TestFolder.docs], names: [docs.displayName])
        }

        await store.send(.offlineRemovalConfirmed) {
            $0.offlineRemoval = nil
            $0.offlineFavoriteIDs = ["C"]
            $0.offlinePinnedFavoriteIDs = ["C"]
        }
        await store.receive(.delegate(.offlineUnpinRequested(path: TestFolder.docs)))
    }

    @Test
    func bulkOfflinePinsTheSelectedFavoritesThatAreNotOfflineYet() async {
        let first = makeFavorite(id: "A", path: Constants.nestedPath)
        let second = makeFavorite(id: "B", path: TestFolder.photos, position: 1)
        let store = store {
            $0.favorites = [first, second]
            $0.isSelecting = true
            $0.selectedFavoriteIDs = ["A", "B"]
            $0.offlineFavoriteIDs = ["A"]
            $0.offlinePinnedFavoriteIDs = ["A"]
        }

        await store.send(.bulkOfflineTapped) {
            $0.isSelecting = false
            $0.selectedFavoriteIDs = []
            $0.offlineFavoriteIDs = ["A", "B"]
            $0.offlinePinnedFavoriteIDs = ["A", "B"]
        }
        await store.receive(.delegate(.offlinePinRequested([second.folderItem])))
    }

    @Test
    func bulkOfflineAsksBeforeUnpinningWhenEverySelectedFavoriteIsPinned() async {
        let first = makeFavorite(id: "A", path: Constants.nestedPath)
        let store = store {
            $0.favorites = [first]
            $0.isSelecting = true
            $0.selectedFavoriteIDs = ["A"]
            $0.offlineFavoriteIDs = ["A"]
            $0.offlinePinnedFavoriteIDs = ["A"]
        }

        await store.send(.bulkOfflineTapped) {
            $0.isSelecting = false
            $0.selectedFavoriteIDs = []
            $0.offlineRemoval = OfflineRemovalRequest(paths: [Constants.nestedPath], names: [first.displayName])
        }
    }

    @Test
    func bulkOfflineWithNothingSelectedDoesNothing() async {
        let store = store { $0.favorites = [makeFavorite(id: "A")] }

        await store.send(.bulkOfflineTapped)
    }

    @Test("A favorite kept only through a pinned parent comes off on its own, under its own name")
    func aFavoriteOfflineThroughAParentComesOffItself() async {
        let favorite = makeFavorite(id: "B", path: Constants.nestedPath)
        let offline = OfflineFileStore.inMemory()
        offline.setPinnedRoots([OfflinePinnedRoot(path: TestFolder.docs, isDirectory: true)])
        var state = FavoritesFeature.State(serverURL: serverURL)
        state.offlineFavoriteIDs = ["B"]
        let store = TestStore(initialState: state) { FavoritesFeature() } withDependencies: {
            $0.offlineFileStore = offline
        }

        await store.send(.offlineToggleTapped(favorite)) {
            $0.offlineRemoval = OfflineRemovalRequest(paths: [favorite.path], names: [favorite.displayName])
        }
    }

    @Test("A favorite offline with no pinned parent found asks nothing")
    func aFavoriteOfflineWithNoPinnedParentAsksNothing() async {
        let favorite = makeFavorite(id: "B", path: Constants.nestedPath)
        let store = store { $0.offlineFavoriteIDs = ["B"] }

        await store.send(.offlineToggleTapped(favorite))
    }

    @Test
    func aFavoriteAtTheRootBuildsAFolderItemWithoutAParent() {
        let favorite = makeFavorite(path: TestFolder.docs)

        #expect(favorite.folderItem.name == TestFolder.docs)
        #expect(favorite.folderItem.path.isEmpty)
        #expect(favorite.folderItem.isDirectory)
        #expect(favorite.folderItem.id == TestFolder.docs)
    }
}
