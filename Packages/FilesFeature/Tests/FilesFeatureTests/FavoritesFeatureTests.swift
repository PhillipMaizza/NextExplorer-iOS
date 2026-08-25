import ComposableArchitecture
import CoreModels
import FilesClient
import Foundation
import Testing

@testable import FilesFeature

@MainActor
@Suite
struct FavoritesFeatureTests {
    private let serverURL = URL(string: "https://example.com")!

    private func makeFavorite(id: String = "1", path: String = "Documents", label: String? = nil) -> Favorite {
        Favorite(id: id, path: path, label: label, icon: "folder", color: nil, position: 0, createdAt: Date(), updatedAt: Date())
    }

    // MARK: Happy path

    @Test
    func onAppearLoadsFavorites() async {
        let favorite = makeFavorite()
        let store = TestStore(initialState: FavoritesFeature.State(serverURL: serverURL)) {
            FavoritesFeature()
        } withDependencies: {
            $0.filesClient.favorites = { _ in [favorite] }
        }

        await store.send(.onAppear) {
            $0.isLoading = true
        }
        await store.receive(\.favoritesResponse.success) {
            $0.isLoading = false
            $0.favorites = [favorite]
        }
    }

    @Test
    func refreshButtonTappedReloadsEvenWhenFavoritesAreAlreadyLoaded() async {
        let existing = makeFavorite(id: "1", path: "Old")
        let refreshed = makeFavorite(id: "2", path: "New")
        var state = FavoritesFeature.State(serverURL: serverURL)
        state.favorites = [existing]

        let store = TestStore(initialState: state) {
            FavoritesFeature()
        } withDependencies: {
            $0.filesClient.favorites = { _ in [refreshed] }
        }

        await store.send(.refreshButtonTapped) {
            $0.isLoading = true
        }
        await store.receive(\.favoritesResponse.success) {
            $0.isLoading = false
            $0.favorites = [refreshed]
        }
    }

    @Test
    func rowTappedEmitsDidSelectDirectoryWithTheFavoritesPathAndDisplayName() async {
        let favorite = makeFavorite(path: "Photos/Vacation", label: "My Trip")
        let store = TestStore(initialState: FavoritesFeature.State(serverURL: serverURL)) {
            FavoritesFeature()
        }

        await store.send(.rowTapped(favorite))
        await store.receive(.delegate(.didSelectDirectory(path: "Photos/Vacation", title: "My Trip")))
    }

    @Test
    func rowTappedWithNoCustomLabelFallsBackToTheLastPathComponent() async {
        let favorite = makeFavorite(path: "Photos/Vacation", label: nil)
        let store = TestStore(initialState: FavoritesFeature.State(serverURL: serverURL)) {
            FavoritesFeature()
        }

        await store.send(.rowTapped(favorite))
        await store.receive(.delegate(.didSelectDirectory(path: "Photos/Vacation", title: "Vacation")))
    }

    // MARK: Error path

    @Test
    func onAppearSurfacesAFavoritesFailureAsAReadableErrorMessage() async {
        let store = TestStore(initialState: FavoritesFeature.State(serverURL: serverURL)) {
            FavoritesFeature()
        } withDependencies: {
            $0.filesClient.favorites = { _ in throw FilesClientError.sessionExpired }
        }

        await store.send(.onAppear) {
            $0.isLoading = true
        }
        await store.receive(\.favoritesResponse.failure) {
            $0.isLoading = false
            $0.errorMessage = FilesClientError.sessionExpired.userMessage
        }
    }

    @Test
    func refreshAfterAFailureClearsThePreviousErrorMessage() async {
        var state = FavoritesFeature.State(serverURL: serverURL)
        state.errorMessage = "Couldn't reach the server."
        let favorite = makeFavorite()

        let store = TestStore(initialState: state) {
            FavoritesFeature()
        } withDependencies: {
            $0.filesClient.favorites = { _ in [favorite] }
        }

        await store.send(.refreshButtonTapped) {
            $0.isLoading = true
            $0.errorMessage = nil
        }
        await store.receive(\.favoritesResponse.success) {
            $0.isLoading = false
            $0.favorites = [favorite]
        }
    }

    // MARK: Edge cases

    @Test
    func onAppearIsANoOpWhenFavoritesAreAlreadyLoaded() async {
        var state = FavoritesFeature.State(serverURL: serverURL)
        state.favorites = [makeFavorite()]

        let store = TestStore(initialState: state) {
            FavoritesFeature()
        }

        // No `filesClient` dependency overridden: a network call here would crash with
        // "Unimplemented", proving the guard skips a redundant fetch.
        await store.send(.onAppear)
    }

    @Test
    func onAppearIsANoOpWhenAnErrorIsAlreadyShowing() async {
        var state = FavoritesFeature.State(serverURL: serverURL)
        state.errorMessage = "Something went wrong."

        let store = TestStore(initialState: state) {
            FavoritesFeature()
        }

        await store.send(.onAppear)
    }

    @Test
    func onAppearIsANoOpWhileAlreadyLoading() async {
        var state = FavoritesFeature.State(serverURL: serverURL)
        state.isLoading = true

        let store = TestStore(initialState: state) {
            FavoritesFeature()
        }

        await store.send(.onAppear)
    }

    @Test
    func favoritesResponseWithAnEmptyListClearsExistingFavorites() async {
        var state = FavoritesFeature.State(serverURL: serverURL)
        state.favorites = [makeFavorite()]

        let store = TestStore(initialState: state) {
            FavoritesFeature()
        }

        await store.send(.favoritesResponse(.success([]))) {
            $0.favorites = []
        }
    }
}
