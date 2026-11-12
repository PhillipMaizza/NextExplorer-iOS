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
struct BrowseFavoritesTests {
    private let vacation = BrowseFixtures.folder("Vacation")

    private func favoritesLoadedState(_ favoritePaths: Set<String> = []) -> BrowseFeature.State {
        var state = BrowseFixtures.state()
        state.favoritePaths = favoritePaths
        state.hasLoadedFavorites = true
        return state
    }

    // MARK: The favorites answer

    @Test("The favorites answer becomes the set of favorite paths and warms those folders into the offline cache")
    func favoritesResponseCollectsFavoritePaths() async {
        let prefetched = LockIsolated<[String]>([])
        let store = BrowseFixtures.store {
            $0.filesClient.prefetchDirectory = { _, path in prefetched.withValue { $0.append(path) } }
            $0.directoryCacheStore.lastWrittenAt = { _, _ in nil }
        }

        await store.send(.favoritesResponse([BrowseFixtures.favorite("Documents")])) {
            $0.favoritePaths = ["Documents"]
            $0.hasLoadedFavorites = true
        }
        await store.finish()
        #expect(prefetched.value == ["Documents"])
    }

    @Test("An empty favorites answer clears the favorite paths and warms nothing")
    func favoritesResponseWithNoFavoritesClearsFavoritePaths() async {
        var state = BrowseFixtures.state()
        state.favoritePaths = ["Documents"]
        // No prefetchDirectory override: a prefetch fails the test as unimplemented.
        let store = BrowseFixtures.store(state)

        await store.send(.favoritesResponse([])) {
            $0.favoritePaths = []
            $0.hasLoadedFavorites = true
        }
        await store.finish()
    }

    @Test("Every favorited folder is warmed into the offline cache")
    func favoritesResponsePrefetchesFavoritedFolders() async {
        let prefetched = LockIsolated<[String]>([])
        let store = BrowseFixtures.store {
            $0.filesClient.prefetchDirectory = { _, path in prefetched.withValue { $0.append(path) } }
            $0.directoryCacheStore.lastWrittenAt = { _, _ in nil }
        }

        await store.send(.favoritesResponse([BrowseFixtures.favorite("Work"), BrowseFixtures.favorite("Trips", position: 1)])) {
            $0.favoritePaths = ["Work", "Trips"]
            $0.hasLoadedFavorites = true
        }
        await store.finish()
        // The folders are warmed side by side, so their order is not fixed.
        #expect(Set(prefetched.value) == ["Work", "Trips"])
        #expect(prefetched.value.count == 2)
    }

    @Test("A favorite that the listing shows as a file is not warmed")
    func favoritesResponseSkipsAFavoriteTheListingShowsAsAFile() async {
        let prefetched = LockIsolated<[String]>([])
        let store = BrowseFixtures.store(BrowseFixtures.state(items: [BrowseFixtures.file("notes.txt")])) {
            $0.filesClient.prefetchDirectory = { _, path in prefetched.withValue { $0.append(path) } }
            $0.directoryCacheStore.lastWrittenAt = { _, _ in nil }
        }

        await store.send(.favoritesResponse([BrowseFixtures.favorite("notes.txt"), BrowseFixtures.favorite("Work", position: 1)])) {
            $0.favoritePaths = ["notes.txt", "Work"]
            $0.hasLoadedFavorites = true
        }
        await store.finish()
        #expect(prefetched.value == ["Work"])
    }

    // MARK: Toggling one folder

    @Test("Two quick taps on the same star send a single request")
    func rapidFavoriteDoubleTapFiresASingleRequest() async {
        let gate = AsyncGate()
        let completions = LockIsolated(0)
        let store = BrowseFixtures.store(favoritesLoadedState()) {
            $0.filesClient.addFavorite = { _, path in
                try await gate.wait()
                completions.withValue { $0 += 1 }
                return BrowseFixtures.favorite(path)
            }
        }

        // Two taps on the same star before the first resolves: the second supersedes the first.
        await store.send(.favoriteToggleButtonTapped(vacation))
        await store.send(.favoriteToggleButtonTapped(vacation))
        gate.open()
        await store.receive(\.favoriteToggleResponse.success) {
            $0.favoritePaths = ["Vacation"]
        }
        await store.receive(.delegate(.favoritesChanged))
        await store.finish()
        #expect(completions.value == 1)
    }

    @Test("A file cannot be favorited, so the tap does nothing")
    func favoriteToggleOnAFileIsANoOpBecauseOnlyFoldersCanBeFavorited() async {
        // The server rejects anything that is not a directory, so this mirrors it without a round trip.
        let store = BrowseFixtures.store(favoritesLoadedState())

        await store.send(.favoriteToggleButtonTapped(BrowseFixtures.file("vacation.jpg")))
    }

    @Test("Tapping a star before the favorites have loaded does nothing")
    func favoriteToggleBeforeFavoritesLoadedIsANoOp() async {
        // Toggling then would add a favorite that may already exist instead of removing it.
        let store = BrowseFixtures.store()

        await store.send(.favoriteToggleButtonTapped(vacation))
    }

    @Test("Starring a folder adds it as a favorite and tells the Favorites tab")
    func favoriteToggleAddsAFavoriteWhenNotAlreadyFavorited() async {
        let added = LockIsolated<[String]>([])
        let store = BrowseFixtures.store(favoritesLoadedState()) {
            $0.filesClient.addFavorite = { _, path in
                added.withValue { $0.append(path) }
                return BrowseFixtures.favorite(path)
            }
        }

        await store.send(.favoriteToggleButtonTapped(vacation))
        await store.receive(\.favoriteToggleResponse.success) {
            $0.favoritePaths = ["Vacation"]
        }
        await store.receive(.delegate(.favoritesChanged))
        #expect(added.value == ["Vacation"])
    }

    @Test("Tapping the star of a favorite removes it and tells the Favorites tab")
    func favoriteToggleRemovesAnExistingFavorite() async {
        let removed = LockIsolated<[String]>([])
        let store = BrowseFixtures.store(favoritesLoadedState(["Vacation"])) {
            $0.filesClient.removeFavorite = { _, path in removed.withValue { $0.append(path) } }
        }

        await store.send(.favoriteToggleButtonTapped(vacation))
        await store.receive(\.favoriteToggleResponse.success) {
            $0.favoritePaths = []
        }
        await store.receive(.delegate(.favoritesChanged))
        #expect(removed.value == ["Vacation"])
    }

    @Test("A failed toggle shows a readable message and keeps the favorites as they were")
    func favoriteToggleFailureSurfacesAReadableErrorMessage() async {
        let store = BrowseFixtures.store(favoritesLoadedState()) {
            $0.filesClient.addFavorite = { _, _ in throw FilesClientError.server(statusCode: 500) }
        }

        await store.send(.favoriteToggleButtonTapped(vacation))
        await store.receive(\.favoriteToggleResponse.failure) {
            $0.fileActionErrorMessage = FilesClientError.server(statusCode: 500).userMessage
        }
    }

    // MARK: Toggling a selection

    @Test("Bulk favorite removes the selected favorites, adds the other selected folders, and skips files")
    func bulkFavoriteTappedTogglesEachSelectedDirectory() async {
        let folder = BrowseFixtures.folder("Photos")
        let alreadyFavorited = BrowseFixtures.folder("Documents")
        let file = BrowseFixtures.file("notes.txt")
        var state = favoritesLoadedState([alreadyFavorited.id])
        state.items = [folder, alreadyFavorited, file]
        state.isSelecting = true
        state.selectedItemIDs = [folder.id, alreadyFavorited.id, file.id]
        let addedPaths = LockIsolated<[String]>([])
        let removedPaths = LockIsolated<[String]>([])
        let store = BrowseFixtures.store(state) {
            $0.filesClient.addFavorite = { _, path in
                addedPaths.withValue { $0.append(path) }
                return BrowseFixtures.favorite(path)
            }
            $0.filesClient.removeFavorite = { _, path in removedPaths.withValue { $0.append(path) } }
        }

        await store.send(.bulkFavoriteTapped) {
            $0.isBulkActionInFlight = true
        }
        await store.receive(\.bulkFavoriteResponse) {
            $0.isBulkActionInFlight = false
            $0.favoritePaths = ["Photos"]
            $0.isSelecting = false
            $0.selectedItemIDs = []
        }
        await store.receive(.delegate(.favoritesChanged))
        #expect(addedPaths.value == ["Photos"])
        #expect(removedPaths.value == ["Documents"])
    }

    @Test("Bulk favorite with a selection that holds no folders does nothing")
    func bulkFavoriteTappedWithNoDirectoriesSelectedDoesNothing() async {
        let file = BrowseFixtures.file("notes.txt")
        var state = favoritesLoadedState()
        state.items = [file]
        state.isSelecting = true
        state.selectedItemIDs = [file.id]
        // No addFavorite or removeFavorite override: a request fails the test as unimplemented.
        let store = BrowseFixtures.store(state)

        await store.send(.bulkFavoriteTapped)
    }

    @Test("A bulk favorite where some requests fail reports how many failed and still updates the rest")
    func bulkFavoriteWithFailuresReportsTheFailedCount() async {
        let works = BrowseFixtures.folder("Works")
        let broken = BrowseFixtures.folder("Broken")
        var state = favoritesLoadedState()
        state.items = [works, broken]
        state.isSelecting = true
        state.selectedItemIDs = [works.id, broken.id]
        let store = BrowseFixtures.store(state) {
            $0.filesClient.addFavorite = { _, path in
                if path == "Broken" { throw FilesClientError.server(statusCode: 500) }
                return BrowseFixtures.favorite(path)
            }
        }

        await store.send(.bulkFavoriteTapped) {
            $0.isBulkActionInFlight = true
        }
        await store.receive(\.bulkFavoriteResponse) {
            $0.isBulkActionInFlight = false
            $0.favoritePaths = ["Works"]
            $0.isSelecting = false
            $0.selectedItemIDs = []
            $0.fileActionErrorMessage = L10n.Browse.bulkFavoriteFailed(1, 2)
        }
        await store.receive(.delegate(.favoritesChanged))
    }

    @Test("Bulk favorite before the favorites have loaded does nothing")
    func bulkFavoriteBeforeFavoritesLoadedIsANoOp() async {
        var state = BrowseFixtures.state(items: [vacation])
        state.isSelecting = true
        state.selectedItemIDs = [vacation.id]
        // No addFavorite or removeFavorite override: a request fails the test as unimplemented.
        let store = BrowseFixtures.store(state)

        await store.send(.bulkFavoriteTapped)
    }

    @Test("A bulk favorite where every request fails changes nothing and reports them all")
    func aFullyFailedBulkFavoriteChangesNothingAndReportsAll() async {
        let first = BrowseFixtures.folder("A")
        let second = BrowseFixtures.folder("B")
        var state = favoritesLoadedState()
        state.items = [first, second]
        state.selectedItemIDs = [first.id, second.id]
        let store = BrowseFixtures.store(state) {
            $0.filesClient.addFavorite = { _, _ in throw FilesClientError.offline }
        }

        await store.send(.bulkFavoriteTapped) {
            $0.isBulkActionInFlight = true
        }
        await store.receive(\.bulkFavoriteResponse) {
            $0.isBulkActionInFlight = false
            $0.isSelecting = false
            $0.selectedItemIDs = []
            $0.fileActionErrorMessage = L10n.Browse.bulkFavoriteFailed(2, 2)
        }
    }

    // MARK: A favorites fetch that fails

    private func reloadingStore(
        favoritePaths: Set<String>,
        hasLoadedFavorites: Bool,
        configure: (inout DependencyValues) -> Void = { _ in }
    ) -> TestStoreOf<BrowseFeature> {
        var state = BrowseFixtures.state("docs", items: [vacation])
        state.favoritePaths = favoritePaths
        state.hasLoadedFavorites = hasLoadedFavorites
        return BrowseFixtures.store(state) {
            $0.serveListing([vacation])
            $0.filesClient.favorites = { _ in throw FilesClientError.server(statusCode: 500) }
            $0.filesClient.prefetchDirectory = { _, _ in }
            $0.directoryCacheStore.lastWrittenAt = { _, _ in nil }
            configure(&$0)
        }
    }

    /// A reload whose favorites request fails: the listing lands, and no favorites answer ever follows.
    private func reload(_ store: TestStoreOf<BrowseFeature>) async {
        await store.send(.onAppear) {
            $0.phase = .loading
        }
        await store.receive(\.itemsResponse.success) {
            $0.phase = .loaded
            $0.access = BrowseTestSupport.readOnlyAccess
        }
        await store.receive(\.offlineAvailabilityComputed)
        await store.finish()
    }

    @Test("A failed favorites fetch keeps the stars the previous answer set")
    func aFailedFavoritesFetchKeepsThePreviousStarsOn() async {
        let store = reloadingStore(favoritePaths: ["Vacation"], hasLoadedFavorites: true)

        await reload(store)

        #expect(store.state.favoritePaths == ["Vacation"])
    }

    @Test("After a failed favorites fetch the next tap on a starred folder removes it instead of adding it again")
    func togglingAfterAFailedFavoritesFetchRemovesInsteadOfAdds() async {
        let removed = LockIsolated<[String]>([])
        let store = reloadingStore(favoritePaths: ["Vacation"], hasLoadedFavorites: true) {
            $0.filesClient.removeFavorite = { _, path in removed.withValue { $0.append(path) } }
        }

        await reload(store)
        await store.send(.favoriteToggleButtonTapped(vacation))
        await store.receive(\.favoriteToggleResponse.success) {
            $0.favoritePaths = []
        }
        await store.receive(.delegate(.favoritesChanged))
        #expect(removed.value == ["Vacation"])
    }

    @Test("When the first favorites fetch fails the stars stay disabled, so a starred folder is never added again")
    func aFailedFirstFavoritesFetchKeepsStarsDisabled() async {
        // No addFavorite or removeFavorite override: a request fails the test as unimplemented.
        let store = reloadingStore(favoritePaths: [], hasLoadedFavorites: false)

        await reload(store)
        await store.send(.favoriteToggleButtonTapped(vacation))

        #expect(!store.state.hasLoadedFavorites)
    }
}
