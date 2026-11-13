import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Testing
import TestUtils

/// Search results kept on this device head the list as "On device", the rest follow as "Remote".
/// Offline, what pinned folders kept still answers a search, under "On device".
@Suite(.isolatedDependencies)
@MainActor
struct SearchOnDeviceTests {
    private enum Constants {
        static let trips = "Trips"
        static let noMatchTerm = "zzzzzz"
        static let tripsPath = "Docs/Trips"
        static let plan = "vacation-plan.pdf"
        static let lookalike = "DocsArchive"
        static let keptCopy = URL(fileURLWithPath: "/tmp/kept.jpg")
    }

    private let photo = BrowseFixtures.file(TestFile.vacationPhoto, in: TestFolder.docs)
    private let trips = BrowseFixtures.folder(Constants.trips, in: TestFolder.docs)
    private let plan = BrowseFixtures.file(Constants.plan, in: Constants.tripsPath)

    private var photoHit: SearchResultItem {
        SearchResultItem(name: TestFile.vacationPhoto, path: TestFolder.docs, kind: SearchResultItem.fileKind)
    }

    private var tripsHit: SearchResultItem {
        SearchResultItem(name: Constants.trips, path: TestFolder.docs, kind: SearchResultItem.directoryKind)
    }

    private var planHit: SearchResultItem {
        SearchResultItem(name: Constants.plan, path: Constants.tripsPath, kind: SearchResultItem.fileKind)
    }

    private let docsFavorite = Favorite(
        id: "1",
        path: TestFolder.docs,
        label: nil,
        icon: "folder",
        color: nil,
        position: 0,
        createdAt: MockDate.date,
        updatedAt: MockDate.date
    )

    /// `Docs/Trips` pinned, with its listing kept on the device.
    private func pinnedTrips() -> OfflineFileStore {
        let offline = OfflineFileStore.inMemory()
        offline.setPinnedRoots([OfflinePinnedRoot(path: Constants.tripsPath, isDirectory: true)])
        offline.saveListing(CachedDirectory(
            path: Constants.tripsPath,
            items: [plan],
            access: BrowseTestSupport.readOnlyAccess,
            fetchedAt: MockDate.date
        ))
        return offline
    }

    private func docsState() -> BrowseFeature.State {
        var state = BrowseFixtures.state(TestFolder.docs, title: TestFolder.docs, items: [photo, trips])
        state.phase = .loaded
        return state
    }

    // MARK: Splitting

    @Test("Results on the device come first, each part in the server's order")
    func sectionsKeepTheServersOrder() {
        let sections = SearchResultSections([photoHit, planHit, tripsHit], onDeviceIDs: [tripsHit.id, planHit.id])

        #expect(sections.onDevice == [planHit, tripsHit])
        #expect(sections.remote == [photoHit])
        #expect(sections.isSplit)
    }

    @Test("With nothing on the device there is one plain list")
    func nothingOnTheDeviceIsOnePlainList() {
        let sections = SearchResultSections([photoHit, planHit], onDeviceIDs: [])

        #expect(sections.onDevice.isEmpty)
        #expect(sections.remote == [photoHit, planHit])
        #expect(!sections.isSplit)
    }

    @Test("Ids left from earlier results split nothing")
    func staleIdsAreIgnored() {
        let sections = SearchResultSections([photoHit], onDeviceIDs: [planHit.id])

        #expect(!sections.isSplit)
        #expect(sections.remote == [photoHit])
    }

    @Test("Everything on the device leaves no Remote part")
    func everythingOnTheDevice() {
        let sections = SearchResultSections([planHit, tripsHit], onDeviceIDs: [planHit.id, tripsHit.id])

        #expect(sections.onDevice == [planHit, tripsHit])
        #expect(sections.remote.isEmpty)
    }

    // MARK: What counts as on the device

    @Test("A pinned item, anything below a pinned folder and a file with a kept copy are on the device")
    func whatCountsAsOnTheDevice() {
        let entries: [(id: String, isDirectory: Bool, hasCopy: Bool)] = [
            (Constants.tripsPath, true, false),
            ("\(Constants.tripsPath)/\(Constants.plan)", false, false),
            ("\(TestFolder.docs)/\(TestFile.vacationPhoto)", false, true),
            ("\(Constants.lookalike)/\(Constants.plan)", false, false),
            ("\(Constants.tripsPath)Old", true, false),
            (TestFolder.photos, true, true),
        ]

        let result = OfflineAvailability.classify(
            entries,
            pinnedPaths: [Constants.tripsPath],
            id: \.id,
            isDirectory: \.isDirectory,
            hasCopy: \.hasCopy
        )

        #expect(result.all == [
            Constants.tripsPath,
            "\(Constants.tripsPath)/\(Constants.plan)",
            "\(TestFolder.docs)/\(TestFile.vacationPhoto)",
        ])
        #expect(result.pinned == [Constants.tripsPath])
    }

    // MARK: Browse

    @Test("Online, a result with a kept copy heads the list and the rest are Remote")
    func onlineAKeptCopyIsOnTheDevice() async {
        var state = docsState()
        state.searchQuery = TestSearch.term
        state.searchResults = [photoHit, planHit]
        let store = BrowseFixtures.store(state) {
            $0.offlineFileStore = .inMemory(localURLs: [photoHit.id: Constants.keptCopy])
        }

        await store.send(.computeSearchOnDevice)
        await store.receive(\.searchOnDeviceComputed) {
            $0.searchOnDeviceIDs = [photoHit.id]
        }

        #expect(store.state.searchResultSections.onDevice == [photoHit])
        #expect(store.state.searchResultSections.remote == [planHit])
    }

    @Test("Offline, a file only a pinned folder kept is still found, and is on the device")
    func offlineAPinnedFolderStillAnswersOnTheDevice() async {
        let clock = TestClock()
        let store = BrowseFixtures.store(docsState()) {
            $0.continuousClock = clock
            $0.directoryCacheStore = DirectoryCacheStore.inMemory()
            $0.offlineFileStore = pinnedTrips()
            $0.filesClient.search = { _, _, _, _ in throw FilesClientError.offline }
        }

        await store.send(.searchQueryChanged(TestSearch.term)) {
            $0.searchQuery = TestSearch.term
            $0.searchResults = [photoHit]
            $0.searchPhase = .loading
        }
        await clock.advance(by: FilesClient.searchDebounce)
        await store.receive(\.searchResultsResponse.failure) {
            $0.searchPhase = .failed(FilesClientError.offline.userMessage)
        }
        await store.receive(\.searchSavedItemsLoaded) {
            $0.searchSavedItems = [plan.id: plan]
            $0.searchResults = [photoHit, planHit]
        }
        await store.send(.computeSearchOnDevice)
        await store.receive(\.searchOnDeviceComputed) {
            $0.searchOnDeviceIDs = [planHit.id]
        }

        #expect(store.state.searchResultSections.onDevice == [planHit])
        #expect(store.state.searchResultSections.remote == [photoHit])
    }

    @Test("Offline, a pinned file is found with the size it was kept with, and is on the device")
    func offlineAPinnedFileIsFound() async {
        let clock = TestClock()
        let planPath = "\(Constants.tripsPath)/\(Constants.plan)"
        let offline = OfflineFileStore.inMemory(copyMetadata: [
            planPath: OfflineCopyMetadata(dateModified: MockDate.date, size: 4_096),
        ])
        offline.setPinnedRoots([OfflinePinnedRoot(path: planPath, isDirectory: false)])
        let kept = FileItem(
            name: Constants.plan,
            path: Constants.tripsPath,
            dateModified: MockDate.date,
            size: 4_096,
            kind: TestKind.pdf
        )
        let store = BrowseFixtures.store(docsState()) {
            $0.continuousClock = clock
            $0.directoryCacheStore = DirectoryCacheStore.inMemory()
            $0.offlineFileStore = offline
            $0.filesClient.search = { _, _, _, _ in throw FilesClientError.offline }
        }

        await store.send(.searchQueryChanged(TestSearch.term)) {
            $0.searchQuery = TestSearch.term
            $0.searchResults = [photoHit]
            $0.searchPhase = .loading
        }
        await clock.advance(by: FilesClient.searchDebounce)
        await store.receive(\.searchResultsResponse.failure) {
            $0.searchPhase = .failed(FilesClientError.offline.userMessage)
        }
        await store.receive(\.searchSavedItemsLoaded) {
            $0.searchSavedItems = [kept.id: kept]
            $0.searchResults = [photoHit, planHit]
        }
        await store.send(.computeSearchOnDevice)
        await store.receive(\.searchOnDeviceComputed) {
            $0.searchOnDeviceIDs = [planHit.id]
        }
    }

    @Test("A folder reached from two starting points is read once")
    func aFolderIsReadOnce() {
        let reads = LockIsolated<[String]>([])
        let listings = [TestFolder.docs: [trips], Constants.tripsPath: [plan]]

        let items = BrowseFeature.savedItems(
            under: [TestFolder.docs, Constants.tripsPath],
            folderLimit: 10,
            itemLimit: 10
        ) { path in
            reads.withValue { $0.append(path) }
            return listings[path]
        }

        #expect(reads.value == [TestFolder.docs, Constants.tripsPath])
        #expect(items == [trips, plan])
    }

    @Test("With no results the lookup clears at once and reads nothing")
    func noResultsClearsAtOnce() async {
        var state = docsState()
        state.searchOnDeviceIDs = [planHit.id]
        let store = BrowseFixtures.store(state)

        await store.send(.computeSearchOnDevice) {
            $0.searchOnDeviceIDs = []
        }
    }

    // MARK: Favorites

    @Test("Favorites search puts what pinned folders keep under On device too")
    func favoritesSplitsItsResults() async {
        var state = FavoritesFeature.State(serverURL: BrowseTestSupport.serverURL)
        state.searchQuery = TestSearch.term
        state.fileSearchResults = [photoHit, planHit]
        let store = TestStore(initialState: state) {
            FavoritesFeature()
        } withDependencies: {
            $0.offlineFileStore = pinnedTrips()
        }

        await store.send(.computeSearchOnDevice)
        await store.receive(\.searchOnDeviceComputed) {
            $0.searchOnDeviceIDs = [planHit.id]
        }

        #expect(store.state.searchResultSections.onDevice == [planHit])
        #expect(store.state.searchResultSections.remote == [photoHit])
    }

    @Test("Favorites search without a connection answers from what the device saved and kept")
    func favoritesSearchOfflineAnswersFromTheDevice() async {
        let clock = TestClock()
        let cache = DirectoryCacheStore.inMemory()
        cache.write(
            serverURL: BrowseTestSupport.serverURL,
            path: TestFolder.docs,
            result: BrowseResult(
                items: [photo, trips],
                access: BrowseTestSupport.readOnlyAccess,
                path: TestFolder.docs
            ),
            etag: nil,
            fetchedAt: MockDate.date
        )
        var state = FavoritesFeature.State(serverURL: BrowseTestSupport.serverURL)
        state.favorites = [docsFavorite]
        let store = TestStore(initialState: state) {
            FavoritesFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.directoryCacheStore = cache
            $0.offlineFileStore = pinnedTrips()
            $0.filesClient.search = { _, _, _, _ in throw FilesClientError.offline }
        }

        await store.send(.searchQueryChanged(TestSearch.term)) {
            $0.searchQuery = TestSearch.term
            $0.searchPhase = .loading
        }
        await clock.advance(by: FilesClient.searchDebounce)
        await store.receive(\.fileSearchResponse.success) {
            $0.fileSearchResults = [photoHit, planHit]
            $0.searchPhase = .loaded
        }
        await store.send(.computeSearchOnDevice)
        await store.receive(\.searchOnDeviceComputed) {
            $0.searchOnDeviceIDs = [planHit.id]
        }
    }

    @Test("Favorites search without a connection and nothing saved still says it is offline")
    func favoritesSearchOfflineWithNothingSaved() async {
        let clock = TestClock()
        var state = FavoritesFeature.State(serverURL: BrowseTestSupport.serverURL)
        state.favorites = [docsFavorite]
        let store = TestStore(initialState: state) {
            FavoritesFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.directoryCacheStore = DirectoryCacheStore.inMemory()
            $0.offlineFileStore = .inMemory()
            $0.filesClient.search = { _, _, _, _ in throw FilesClientError.offline }
        }

        await store.send(.searchQueryChanged(TestSearch.term)) {
            $0.searchQuery = TestSearch.term
            $0.searchPhase = .loading
        }
        await clock.advance(by: FilesClient.searchDebounce)
        await store.receive(\.fileSearchResponse.failure) {
            $0.searchPhase = .failed(FilesClientError.offline.userMessage)
        }
    }

    @Test("Favorites search without a connection over saved data that matches nothing answers with no results")
    func favoritesSearchOfflineWithSavedDataButNoMatch() async {
        let clock = TestClock()
        let cache = DirectoryCacheStore.inMemory()
        cache.write(
            serverURL: BrowseTestSupport.serverURL,
            path: TestFolder.docs,
            result: BrowseResult(items: [photo], access: BrowseTestSupport.readOnlyAccess, path: TestFolder.docs),
            etag: nil,
            fetchedAt: MockDate.date
        )
        var state = FavoritesFeature.State(serverURL: BrowseTestSupport.serverURL)
        state.favorites = [docsFavorite]
        let store = TestStore(initialState: state) {
            FavoritesFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.directoryCacheStore = cache
            $0.offlineFileStore = .inMemory()
            $0.filesClient.search = { _, _, _, _ in throw FilesClientError.offline }
        }

        await store.send(.searchQueryChanged(Constants.noMatchTerm)) {
            $0.searchQuery = Constants.noMatchTerm
            $0.searchPhase = .loading
        }
        await clock.advance(by: FilesClient.searchDebounce)
        await store.receive(\.fileSearchResponse.success) {
            $0.fileSearchResults = []
            $0.searchPhase = .loaded
        }
    }

    @Test("A change in what is kept offline finds the on device results again")
    func favoritesRecomputesOnDeviceWhenAvailabilityChanges() async {
        var state = FavoritesFeature.State(serverURL: BrowseTestSupport.serverURL)
        state.searchQuery = TestSearch.term
        state.fileSearchResults = [photoHit, planHit]
        let store = TestStore(initialState: state) {
            FavoritesFeature()
        } withDependencies: {
            $0.offlineFileStore = pinnedTrips()
        }

        await store.send(.offlineAvailabilityChanged)
        await store.receive(\.computeSearchOnDevice)
        await store.receive(\.searchOnDeviceComputed) {
            $0.searchOnDeviceIDs = [planHit.id]
        }
    }

    @Test("Without search results a change in what is kept offline starts no lookup")
    func favoritesWithoutResultsStartsNoLookup() async {
        let store = TestStore(initialState: FavoritesFeature.State(serverURL: BrowseTestSupport.serverURL)) {
            FavoritesFeature()
        }

        await store.send(.offlineAvailabilityChanged)
    }
}
