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
struct FavoritesSelectionAndRemovalTests: FavoritesTestSupport {
    @Test
    func rapidRemoveDoubleTapFiresASingleRequest() async {
        let favorite = makeFavorite(id: "1", path: TestFolder.documents)
        var state = FavoritesFeature.State(serverURL: serverURL)
        state.favorites = [favorite]
        let gate = AsyncGate()
        let completions = LockIsolated(0)

        let store = TestStore(initialState: state) {
            FavoritesFeature()
        } withDependencies: {
            $0.filesClient.removeFavorite = { _, _ in
                try await gate.wait()
                completions.withValue { $0 += 1 }
            }
        }

        // The second tap cancels the first request, so only one reaches the end of the gate.
        await store.send(.removeTapped(favorite))
        await store.send(.removeTapped(favorite))
        gate.open()
        await store.receive(\.removeResponse) { $0.favorites = [] }

        #expect(completions.value == 1)
    }

    @Test
    func selectModeTogglesAndClearsSelection() async {
        var state = FavoritesFeature.State(serverURL: serverURL)
        state.selectedFavoriteIDs = ["1"]

        let store = TestStore(initialState: state) {
            FavoritesFeature()
        }

        await store.send(.selectModeToggled) {
            $0.isSelecting = true
            $0.selectedFavoriteIDs = []
        }
    }

    @Test
    func itemSelectionToggledAddsThenRemovesTheSameID() async {
        var state = FavoritesFeature.State(serverURL: serverURL)
        state.isSelecting = true

        let store = TestStore(initialState: state) {
            FavoritesFeature()
        }

        await store.send(.itemSelectionToggled("1")) {
            $0.selectedFavoriteIDs = ["1"]
        }
        await store.send(.itemSelectionToggled("1")) {
            $0.selectedFavoriteIDs = []
        }
    }

    @Test
    func selectAllAndDeselectAllTapped() async {
        let a = makeFavorite(id: "1", path: "A")
        let b = makeFavorite(id: "2", path: "B")
        var state = FavoritesFeature.State(serverURL: serverURL)
        state.favorites = [a, b]
        state.isSelecting = true

        let store = TestStore(initialState: state) {
            FavoritesFeature()
        }

        await store.send(.selectAllTapped) {
            $0.selectedFavoriteIDs = ["1", "2"]
        }
        await store.send(.deselectAllTapped) {
            $0.selectedFavoriteIDs = []
        }
    }

    @Test
    func removeTappedRemovesASingleFavoriteOnSuccess() async {
        let favorite = makeFavorite(path: TestFolder.photos)
        var state = FavoritesFeature.State(serverURL: serverURL)
        state.favorites = [favorite]

        let store = TestStore(initialState: state) {
            FavoritesFeature()
        } withDependencies: {
            $0.filesClient.removeFavorite = { _, _ in }
        }

        await store.send(.removeTapped(favorite))
        await store.receive(\.removeResponse) {
            $0.favorites = []
        }
    }

    @Test
    func bulkRemoveConfirmedRemovesEverySelectedFavorite() async {
        let a = makeFavorite(id: "1", path: "A")
        let b = makeFavorite(id: "2", path: "B")
        var state = FavoritesFeature.State(serverURL: serverURL)
        state.favorites = [a, b]
        state.isSelecting = true
        state.selectedFavoriteIDs = ["1", "2"]

        let store = TestStore(initialState: state) {
            FavoritesFeature()
        } withDependencies: {
            $0.filesClient.removeFavorite = { _, _ in }
        }

        await store.send(.bulkRemoveTapped) {
            $0.bulkRemoveConfirmationIsPresented = true
        }
        await store.send(.bulkRemoveConfirmed) {
            $0.bulkRemoveConfirmationIsPresented = false
        }
        await store.receive(\.bulkRemoveResponse) {
            $0.favorites = []
            $0.isSelecting = false
            $0.selectedFavoriteIDs = []
        }
    }

    @Test
    func bulkRemoveTappedWithNoSelectionDoesNothing() async {
        let store = TestStore(initialState: FavoritesFeature.State(serverURL: serverURL)) {
            FavoritesFeature()
        }

        await store.send(.bulkRemoveTapped)
    }
}
