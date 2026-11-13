import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Localization
import Testing
import TestUtils

/// Listings saved on the device answer a search only where the server cannot: a term too short to
/// send, or no server to reach. A real server error never falls back to them.
@Suite(.isolatedDependencies)
@MainActor
struct BrowseSavedSearchTests {
    private enum Constants {
        static let trips = "Trips"
        static let tripsPath = "Docs/Trips"
        static let deepPhoto = "vacation-plan.pdf"
        static let unopened = "Unopened"
        static let unopenedPath = "Docs/Unopened"
        static let serverError = 500
        static let oneLetter = "v"
    }

    private let photo = BrowseFixtures.file(TestFile.vacationPhoto, in: TestFolder.docs)
    private let trips = BrowseFixtures.folder(Constants.trips, in: TestFolder.docs)
    private let unopened = BrowseFixtures.folder(Constants.unopened, in: TestFolder.docs)
    private let deepPhoto = BrowseFixtures.file(Constants.deepPhoto, in: Constants.tripsPath)

    private var photoMatch: SearchResultItem {
        SearchResultItem(name: TestFile.vacationPhoto, path: TestFolder.docs, kind: SearchResultItem.fileKind)
    }

    private var deepMatch: SearchResultItem {
        SearchResultItem(name: Constants.deepPhoto, path: Constants.tripsPath, kind: SearchResultItem.fileKind)
    }

    /// `Docs` and `Docs/Trips` saved on the device; `Docs/Unopened` was never opened.
    private func savedListings() -> DirectoryCacheStore {
        let cache = DirectoryCacheStore.inMemory()
        let access = BrowseTestSupport.readOnlyAccess
        cache.write(serverURL: BrowseTestSupport.serverURL, path: TestFolder.docs, result: BrowseResult(items: [photo, trips, unopened], access: access, path: TestFolder.docs), etag: nil, fetchedAt: MockDate.date)
        cache.write(serverURL: BrowseTestSupport.serverURL, path: Constants.tripsPath, result: BrowseResult(items: [deepPhoto], access: access, path: Constants.tripsPath), etag: nil, fetchedAt: MockDate.date)
        return cache
    }

    private func docsState() -> BrowseFeature.State {
        var state = BrowseFixtures.state(TestFolder.docs, title: TestFolder.docs, items: [photo, trips, unopened])
        state.phase = .loaded
        return state
    }

    private var savedByID: [String: FileItem] {
        Dictionary(uniqueKeysWithValues: [photo, trips, unopened, deepPhoto].map { ($0.id, $0) })
    }

    @Test("Saved folders are read below the search's folder, only through folders that were saved, up to both limits")
    func savedFoldersAreReadThroughSavedFoldersOnly() {
        let listings = [
            "": [BrowseFixtures.folder(TestFolder.docs)],
            TestFolder.docs: [trips, unopened, photo],
            Constants.tripsPath: [deepPhoto],
        ]
        let reads = LockIsolated<[String]>([])
        let read: (String) -> [FileItem]? = { path in
            reads.withValue { $0.append(path) }
            return listings[path]
        }

        let items = BrowseFeature.savedItems(under: TestFolder.docs, folderLimit: 10, itemLimit: 10, read: read)
        #expect(Set(items.map(\.id)) == Set([trips.id, unopened.id, photo.id, deepPhoto.id]))
        #expect(reads.value == [TestFolder.docs, Constants.tripsPath, Constants.unopenedPath])

        reads.setValue([])
        #expect(BrowseFeature.savedItems(under: "", folderLimit: 2, itemLimit: 10, read: read).count == 4)
        #expect(reads.value == ["", TestFolder.docs])

        // The item limit stops the walk too, keeping only what fits.
        reads.setValue([])
        #expect(BrowseFeature.savedItems(under: TestFolder.docs, folderLimit: 10, itemLimit: 2, read: read).map(\.id) == [trips.id, unopened.id])
        #expect(reads.value == [TestFolder.docs])
    }

    @Test("A term too short for the server also finds what saved folders below hold")
    func aShortTermFindsSavedFolders() async {
        let store = BrowseFixtures.store(docsState()) {
            $0.directoryCacheStore = savedListings()
        }

        await store.send(.searchQueryChanged(TestSearch.shortTerm)) {
            $0.searchQuery = TestSearch.shortTerm
            $0.searchResults = [photoMatch]
        }
        await store.receive(\.searchSavedItemsLoaded) {
            $0.searchSavedItems = savedByID
            $0.searchResults = [photoMatch, deepMatch]
        }
    }

    @Test("Offline, the saved folders answer and the footer says the server cannot be reached")
    func offlineTheSavedFoldersAnswer() async {
        let clock = TestClock()
        let store = BrowseFixtures.store(docsState()) {
            $0.continuousClock = clock
            $0.directoryCacheStore = savedListings()
            $0.filesClient.search = { _, _, _, _ in throw FilesClientError.offline }
        }

        await store.send(.searchQueryChanged(TestSearch.term)) {
            $0.searchQuery = TestSearch.term
            $0.searchResults = [photoMatch]
            $0.searchPhase = .loading
        }
        await clock.advance(by: FilesClient.searchDebounce)
        await store.receive(\.searchResultsResponse.failure) {
            $0.searchPhase = .failed(FilesClientError.offline.userMessage)
        }
        #expect(store.state.isSearchOffline)
        await store.receive(\.searchSavedItemsLoaded) {
            $0.searchSavedItems = savedByID
            $0.searchResults = [photoMatch, deepMatch]
        }
        #expect(store.state.searchFailureMessage == FilesClientError.offline.userMessage)
    }

    @Test("A real server error never answers from saved folders, even ones already read")
    func aServerErrorNeverAnswersFromSavedFolders() async {
        let clock = TestClock()
        var state = docsState()
        state.searchQuery = TestSearch.shortTerm
        state.searchSavedItems = savedByID
        state.searchResults = [photoMatch, deepMatch]
        let store = BrowseFixtures.store(state) {
            $0.continuousClock = clock
            $0.directoryCacheStore = savedListings()
            $0.filesClient.search = { _, _, _, _ in throw FilesClientError.server(statusCode: Constants.serverError) }
        }

        await store.send(.searchQueryChanged(TestSearch.term)) {
            $0.searchQuery = TestSearch.term
            $0.searchResults = [photoMatch]
            $0.searchPhase = .loading
        }
        await clock.advance(by: FilesClient.searchDebounce)
        await store.receive(\.searchResultsResponse.failure) {
            $0.searchPhase = .failed(L10n.Browse.searchFailed)
        }
        #expect(store.state.searchResults == [photoMatch])
    }

    @Test("Saved folders are read once a search, and forgotten when it ends or its folder changes")
    func savedFoldersAreReadOnceAndForgotten() async {
        let reads = LockIsolated(0)
        let cache = savedListings()
        let counting = DirectoryCacheStore(
            read: { serverURL, path in
                reads.withValue { $0 += 1 }
                return cache.read(serverURL: serverURL, path: path)
            },
            lastWrittenAt: cache.lastWrittenAt,
            write: cache.write,
            touch: cache.touch,
            remove: cache.remove,
            clearAll: cache.clearAll,
            totalSizeBytes: cache.totalSizeBytes
        )
        let store = BrowseFixtures.store(docsState()) {
            $0.directoryCacheStore = counting
        }

        await store.send(.searchQueryChanged(TestSearch.shortTerm)) {
            $0.searchQuery = TestSearch.shortTerm
            $0.searchResults = [photoMatch]
        }
        await store.receive(\.searchSavedItemsLoaded) {
            $0.searchSavedItems = savedByID
            $0.searchResults = [photoMatch, deepMatch]
        }
        let readsForOneSearch = reads.value
        await store.send(.searchQueryChanged(Constants.oneLetter)) {
            $0.searchQuery = Constants.oneLetter
            $0.searchResults = [photoMatch, deepMatch]
        }
        #expect(reads.value == readsForOneSearch)

        // Everywhere reads from the root, which was never saved: nothing below it is known.
        await store.send(.searchScopeChanged(.everywhere)) {
            $0.searchScope = .everywhere
            $0.searchSavedItems = nil
            $0.searchResults = [photoMatch]
        }
        await store.receive(\.searchSavedItemsLoaded) {
            $0.searchSavedItems = [:]
        }

        await store.send(.searchQueryChanged("")) {
            $0.searchQuery = ""
            $0.searchResults = nil
            $0.searchSavedItems = nil
            $0.searchScope = .thisFolder
        }
        #expect(reads.value == readsForOneSearch + 1)
    }
}
