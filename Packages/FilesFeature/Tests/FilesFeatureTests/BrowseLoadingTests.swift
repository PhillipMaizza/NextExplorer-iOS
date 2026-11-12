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
struct BrowseLoadingTests {
    private let readOnlyAccess = BrowseTestSupport.readOnlyAccess

    @Test("Appearing loads the listing, then the favorites, then which items are available offline")
    func onAppearLoadsRootItems() async {
        let item = BrowseFixtures.folder(TestFolder.docs)
        let favorites = AsyncGate()
        let store = BrowseFixtures.store {
            $0.serveEmptyFolders()
            $0.serveListing([item])
            $0.holdFavorites(favorites)
        }

        await store.send(.onAppear) {
            $0.phase = .loading
        }
        await store.receive(\.itemsResponse.success) {
            $0.phase = .loaded
            $0.items = [item]
            $0.access = readOnlyAccess
        }
        await store.receive(\.offlineAvailabilityComputed)
        favorites.open()
        await store.receive(\.favoritesResponse) {
            $0.hasLoadedFavorites = true
        }
        await store.finish()
    }

    @Test("Appearing on an empty folder loads it with no items and no offline check")
    func onAppearWithAnEmptyFolderLoadsSuccessfullyWithNoItems() async {
        let store = BrowseFixtures.store { $0.serveEmptyFolders() }

        await store.send(.onAppear) {
            $0.phase = .loading
        }
        await store.receive(\.itemsResponse.success) {
            $0.phase = .loaded
            $0.access = readOnlyAccess
        }
        await store.receive(\.favoritesResponse) {
            $0.hasLoadedFavorites = true
        }
    }

    @Test("A failed browse shows its readable message, and the favorites still load")
    func onAppearSurfacesABrowseFailureAsAReadableErrorMessage() async {
        let store = BrowseFixtures.store {
            $0.serveEmptyFolders()
            $0.filesClient.browse = { _, _ in throw FilesClientError.sessionExpired }
        }

        await store.send(.onAppear) {
            $0.phase = .loading
        }
        await store.receive(\.itemsResponse.failure) {
            $0.phase = .failed(FilesClientError.sessionExpired.userMessage)
        }
        await store.receive(\.favoritesResponse) {
            $0.hasLoadedFavorites = true
        }
    }

    @Test(
        "Appearing again after a load started, finished or failed does not fetch again",
        arguments: [DataPhase.loaded, .loading, .failed("Something went wrong.")]
    )
    func onAppearIsANoOpOnceALoadHasStarted(phase: DataPhase) async {
        var state = BrowseFixtures.state()
        state.phase = phase
        // No filesClient override: a fetch would fail the test as unimplemented.
        let store = BrowseFixtures.store(state)

        await store.send(.onAppear)
    }

    @Test("The refresh button reloads even when items are already loaded")
    func refreshButtonTappedReloadsEvenWhenItemsAreAlreadyLoaded() async {
        let refreshed = BrowseFixtures.file("New.txt")
        var state = BrowseFixtures.state(items: [BrowseFixtures.file("Old.txt")])
        state.phase = .loaded
        let favorites = AsyncGate()
        let store = BrowseFixtures.store(state) {
            $0.serveEmptyFolders()
            $0.serveListing([refreshed])
            $0.holdFavorites(favorites)
        }

        await store.send(.refreshButtonTapped) {
            $0.phase = .loading
        }
        await store.receive(\.itemsResponse.success) {
            $0.phase = .loaded
            $0.items = [refreshed]
            $0.access = readOnlyAccess
        }
        await store.receive(\.offlineAvailabilityComputed)
        favorites.open()
        await store.receive(\.favoritesResponse) {
            $0.hasLoadedFavorites = true
        }
    }

    @Test("A failed refresh of a folder that shows items keeps them and reports the error as a toast")
    func aFailedRefreshKeepsTheListAndShowsAToast() async {
        let items = [BrowseFixtures.file(TestFile.aText, in: TestPath.docsLowercase), BrowseFixtures.file(TestFile.bText, in: TestPath.docsLowercase)]
        let favorites = AsyncGate()
        let store = BrowseFixtures.store(BrowseFixtures.loadedState(TestPath.docsLowercase, items: items)) {
            $0.serveEmptyFolders()
            $0.filesClient.browse = { _, _ in throw FilesClientError.server(statusCode: 500) }
            $0.holdFavorites(favorites)
        }

        await store.send(.refreshButtonTapped) {
            $0.phase = .loading
        }
        await store.receive(\.itemsResponse.failure) {
            $0.phase = .loaded
            $0.fileActionErrorMessage = FilesClientError.server(statusCode: 500).userMessage
        }
        await store.receive(\.offlineAvailabilityComputed)
        favorites.open()
        await store.receive(\.favoritesResponse) {
            $0.hasLoadedFavorites = true
        }
    }

    @Test("Loading the root asks the server for its features and shows My Files when personal space is on")
    func rootLoadFetchesServerFeaturesAndShowsThePersonalSpace() async {
        let volume = BrowseFixtures.folder(TestFolder.files)
        let features = AsyncGate()
        let listing = AsyncGate()
        let favorites = AsyncGate()
        let store = BrowseFixtures.store {
            $0.serveEmptyFolders()
            $0.filesClient.browse = { _, path in
                try await listing.wait()
                return BrowseResult(items: [volume], access: BrowseTestSupport.fullAccess, path: path)
            }
            $0.filesClient.serverFeatures = { _ in
                try await features.wait()
                return ServerFeatures(isPersonalEnabled: true)
            }
            $0.filesClient.favorites = { _ in
                try await favorites.wait()
                return []
            }
        }

        await store.send(.refreshButtonTapped) {
            $0.phase = .loading
        }
        features.open()
        await store.receive(\.serverFeaturesResponse) {
            $0.isPersonalSpaceEnabled = true
        }
        listing.open()
        await store.receive(\.itemsResponse.success) {
            $0.phase = .loaded
            $0.items = [volume]
            $0.access = BrowseTestSupport.fullAccess
        }
        await store.receive(\.offlineAvailabilityComputed)
        favorites.open()
        await store.receive(\.favoritesResponse) {
            $0.hasLoadedFavorites = true
        }
        await store.finish()
    }

    @Test("A subfolder load never asks for server features")
    func subfolderLoadNeverAsksForServerFeatures() async {
        let store = BrowseFixtures.store(BrowseFixtures.state(TestFolder.files, title: TestFolder.files)) {
            $0.serveEmptyFolders()
            $0.filesClient.serverFeatures = { _ in
                Issue.record("only the root screen offers the personal space")
                throw FilesClientError.offline
            }
        }

        await store.send(.refreshButtonTapped) {
            $0.phase = .loading
        }
        await store.receive(\.itemsResponse.success) {
            $0.phase = .loaded
            $0.access = readOnlyAccess
        }
        await store.receive(\.favoritesResponse) {
            $0.hasLoadedFavorites = true
        }
    }

    @Test("The root paints the last known personal space answer from the first frame of the next launch")
    func theRootPaintsTheLastKnownPersonalSpaceAnswerBeforeAnyFetch() async {
        let cache = JSONCacheStore.inMemory()
        let store = TestStore(initialState: withDependencies {
            $0.jsonCacheStore = cache
        } operation: {
            BrowseFixtures.state()
        }) {
            BrowseFeature()
        } withDependencies: {
            $0.jsonCacheStore = cache
        }
        #expect(!store.state.isPersonalSpaceEnabled)

        await store.send(.serverFeaturesResponse(ServerFeatures(isPersonalEnabled: true))) {
            $0.isPersonalSpaceEnabled = true
        }
        await store.finish()

        let next = withDependencies {
            $0.jsonCacheStore = cache
        } operation: {
            BrowseFixtures.state()
        }
        #expect(next.isPersonalSpaceEnabled, "the next launch should show My Files from the first frame")
        let subfolder = withDependencies {
            $0.jsonCacheStore = cache
        } operation: {
            BrowseFixtures.state(TestFolder.files, title: TestFolder.files)
        }
        #expect(!subfolder.isPersonalSpaceEnabled)
    }

    @Test("Tapping My Files opens the personal path under its title")
    func personalSpaceTappedOpensThePersonalPathAsMyFiles() async {
        let store = BrowseFixtures.store()

        await store.send(.personalSpaceTapped)
        await store.receive(.delegate(.openPath(path: "personal", title: L10n.Browse.myFiles)))
    }
}
