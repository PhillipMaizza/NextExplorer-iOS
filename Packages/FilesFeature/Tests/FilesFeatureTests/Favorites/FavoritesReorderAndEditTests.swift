import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Localization
import Testing
import TestUtils

@Suite(.isolatedDependencies)
@MainActor
struct FavoritesReorderAndEditTests: FavoritesTestSupport {
    @Test
    func loadOrdersFavoritesByPositionRegardlessOfResponseOrder() async {
        let first = makeFavorite(id: "1", path: "Alpha", position: 0)
        let second = makeFavorite(id: "2", path: "Beta", position: 1)
        let store = TestStore(initialState: FavoritesFeature.State(serverURL: serverURL)) {
            FavoritesFeature()
        } withDependencies: {
            $0.filesClient.favorites = { _ in [second, first] }
        }

        await store.send(.onAppear) { $0.phase = .loading }
        await store.receive(\.favoritesResponse.success) {
            $0.phase = .loaded
            $0.favorites = [first, second]
        }
        await store.receive(\.offlineAvailabilityComputed)

        #expect(store.state.displayedFavorites == [first, second])
    }

    @Test
    func movingAFavoriteReordersOptimisticallyAndPatchesTheFullOrder() async {
        let a = makeFavorite(id: "a", path: "A", position: 0)
        let b = makeFavorite(id: "b", path: "B", position: 1)
        let c = makeFavorite(id: "c", path: "C", position: 2)
        let reordered = [
            makeFavorite(id: "c", path: "C", position: 0),
            makeFavorite(id: "a", path: "A", position: 1),
            makeFavorite(id: "b", path: "B", position: 2),
        ]
        var state = FavoritesFeature.State(serverURL: serverURL)
        state.favorites = [a, b, c]

        let recorded = LockIsolated<[String]?>(nil)
        let store = TestStore(initialState: state) {
            FavoritesFeature()
        } withDependencies: {
            $0.filesClient.reorderFavorites = { _, ids in
                recorded.setValue(ids)
                return reordered
            }
        }

        // Move C to the front.
        await store.send(.favoritesMoved(IndexSet(integer: 2), 0)) { $0.favorites = [c, a, b] }
        await store.receive(\.reorderResponse.success) { $0.favorites = IdentifiedArray(uniqueElements: reordered) }
        await store.receive(.delegate(.favoritesChanged))

        #expect(recorded.value == ["c", "a", "b"])
    }

    @Test
    func aFailedReorderShowsAToastAndRefetchesTheAuthoritativeOrder() async {
        let a = makeFavorite(id: "a", path: "A", position: 0)
        let b = makeFavorite(id: "b", path: "B", position: 1)
        var state = FavoritesFeature.State(serverURL: serverURL)
        state.favorites = [a, b]

        let store = TestStore(initialState: state) {
            FavoritesFeature()
        } withDependencies: {
            $0.filesClient.reorderFavorites = { _, _ in throw FilesClientError.network(TestFailure.offline) }
            $0.filesClient.favorites = { _ in [a, b] }
        }

        await store.send(.favoritesMoved(IndexSet(integer: 1), 0)) { $0.favorites = [b, a] }
        await store.receive(\.reorderResponse.failure) {
            $0.actionErrorMessage = L10n.Favorites.reorderFailed
            $0.phase = .loading
        }
        await store.receive(\.favoritesResponse.success) {
            $0.phase = .loaded
            $0.favorites = [a, b]
        }
        await store.receive(\.offlineAvailabilityComputed)
    }

    @Test
    func reorderIsIgnoredWhileSearching() async {
        let a = makeFavorite(id: "a", path: "A", position: 0)
        let b = makeFavorite(id: "b", path: "B", position: 1)
        var state = FavoritesFeature.State(serverURL: serverURL)
        state.favorites = [a, b]
        state.searchQuery = "a"

        let store = TestStore(initialState: state) { FavoritesFeature() }

        await store.send(.favoritesMoved(IndexSet(integer: 1), 0))
    }

    @Test
    func editTappedPresentsTheSheetAndAnUpdateSwapsTheRow() async {
        let favorite = makeFavorite(id: "f1", path: TestFolder.documents, label: TestFolder.docs)
        var state = FavoritesFeature.State(serverURL: serverURL)
        state.favorites = [favorite]

        let store = TestStore(initialState: state) { FavoritesFeature() }

        await store.send(.editTapped(favorite)) {
            $0.editSheet = FavoriteEditFeature.State(serverURL: serverURL, favorite: favorite)
        }

        let updated = Favorite(
            id: "f1", path: TestFolder.documents, label: "Projects", icon: "solid:BriefcaseIcon", color: "#009cff",
            position: 0, createdAt: favorite.createdAt, updatedAt: MockDate.date
        )
        await store.send(.editSheet(.presented(.delegate(.updated(updated))))) {
            $0.favorites[id: "f1"] = updated
            $0.editSheet = nil
        }
        await store.receive(.delegate(.favoritesChanged))
    }
}
