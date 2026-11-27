import ComposableArchitecture
import CoreModels
import DesignSystem
import FilesClient
@testable import FilesFeature
import Foundation
import Localization
import Testing
import TestUtils

@Suite(.isolatedDependencies)
@MainActor
struct SearchMyFilesAndVolumesTests {
    private enum Constants {
        static let query = "plan"
        static let myFilesFolder = "personal/Docs"
        static let volumeFolder = "Files/Docs"
    }

    private let myHit = SearchResultItem(name: "Trip plan.txt", path: "personal", kind: "file", isNameMatch: true)
    private let volumeHit = SearchResultItem(
        name: "Project plan.pdf",
        path: "Files",
        kind: "file",
        isNameMatch: true
    )
    private let volumeFolderHit = SearchResultItem(
        name: "Floor plans",
        path: "Files",
        kind: "dir",
        isNameMatch: true
    )

    private struct Asked: Equatable {
        let path: String
        let limit: Int?
    }

    private func store(
        _ path: String,
        clock: TestClock<Duration>,
        asked: LockIsolated<[Asked]>,
        volumesGate: AsyncGate? = nil,
        volumes: @escaping @Sendable () throws -> SearchPage
    ) -> TestStoreOf<BrowseFeature> {
        var state = BrowseFixtures.state(path)
        state.searchScope = .everywhere
        let myHit = myHit
        return BrowseFixtures.store(state) {
            $0.continuousClock = clock
            $0.filesClient.search = { _, path, _, limit in
                asked.withValue { $0.append(Asked(path: path, limit: limit)) }
                guard path.isEmpty else { return [myHit] }
                try await volumesGate?.wait()
                return try volumes()
            }
        }
    }

    private func typeQuery(_ store: TestStoreOf<BrowseFeature>, splits: Bool) async {
        await store.send(.searchQueryChanged(Constants.query)) {
            $0.searchQuery = Constants.query
            $0.searchResults = []
            $0.searchPhase = .loading
            if splits {
                $0.volumeSearch.phase = .loading
            }
        }
    }

    @Test("From My Files, Everywhere asks My Files and the volumes, each answer in its own section")
    func myFilesAsksBothLanes() async {
        let clock = TestClock()
        let asked = LockIsolated<[Asked]>([])
        let gate = AsyncGate()
        let volumes = [volumeHit]
        let store = store(Constants.myFilesFolder, clock: clock, asked: asked, volumesGate: gate) {
            SearchPage(items: volumes)
        }

        await typeQuery(store, splits: true)
        await clock.advance(by: FilesClient.searchDebounce)
        await store.receive(\.searchResultsResponse) {
            $0.searchPhase = .loaded
            $0.searchResults = [myHit]
            $0.searchAnsweredTerm = Constants.query
        }
        gate.open()
        await store.receive(\.searchVolumesResponse) {
            $0.volumeSearch.phase = .loaded
            $0.volumeSearch.results = volumes
        }

        #expect(Set(asked.value.map(\.path)) == ["", PersonalSpace.rootPath])
        #expect(store.state.searchHit(id: volumeHit.id) == volumeHit)
        #expect(!store.state.isEverySearchLaneEmpty)
    }

    @Test("From a volume, Everywhere stays one request")
    func aVolumeAsksOnce() async {
        let clock = TestClock()
        let asked = LockIsolated<[Asked]>([])
        let store = store(Constants.volumeFolder, clock: clock, asked: asked) { [] }

        await typeQuery(store, splits: false)
        await clock.advance(by: FilesClient.searchDebounce)
        await store.receive(\.searchResultsResponse) {
            $0.searchPhase = .loaded
            $0.searchAnsweredTerm = Constants.query
        }

        #expect(asked.value.map(\.path) == [""])
    }

    @Test("Clearing the term before the wait ends asks neither lane")
    func clearingCancelsBothLanes() async {
        let clock = TestClock()
        let asked = LockIsolated<[Asked]>([])
        let store = store(Constants.myFilesFolder, clock: clock, asked: asked) { [] }

        await typeQuery(store, splits: true)
        await store.send(.searchQueryChanged("")) {
            $0.searchQuery = ""
            $0.searchResults = nil
            $0.searchPhase = .idle
            $0.searchScope = .thisFolder
            $0.volumeSearch = BrowseFeature.VolumeSearch()
        }
        await clock.advance(by: FilesClient.searchDebounce)

        #expect(asked.value.isEmpty)
    }

    struct FailureCase: Sendable, CustomTestStringConvertible {
        let error: FilesClientError
        let phase: DataPhase

        var testDescription: String {
            "\(error)"
        }
    }

    @Test("A volumes failure says so in its section; an account with no volumes just has none", arguments: [
        FailureCase(error: .server(statusCode: 500), phase: .failed(L10n.Browse.searchFailed)),
        FailureCase(error: .forbidden(message: "You do not have access to this volume"), phase: .loaded),
        FailureCase(error: .serverMessage(statusCode: 404, message: "Base path not found."), phase: .loaded),
        FailureCase(error: .offline, phase: .loaded),
    ])
    func volumesFailure(_ testCase: FailureCase) async {
        let clock = TestClock()
        let asked = LockIsolated<[Asked]>([])
        let gate = AsyncGate()
        let error = testCase.error
        let store = store(Constants.myFilesFolder, clock: clock, asked: asked, volumesGate: gate) {
            throw error
        }

        await typeQuery(store, splits: true)
        await clock.advance(by: FilesClient.searchDebounce)
        await store.receive(\.searchResultsResponse) {
            $0.searchPhase = .loaded
            $0.searchResults = [myHit]
            $0.searchAnsweredTerm = Constants.query
        }
        gate.open()
        await store.receive(\.searchVolumesResponse) {
            $0.volumeSearch.phase = testCase.phase
        }
    }

    @Test("Show more in Volumes asks the volumes for more and leaves My Files alone")
    func showMoreVolumes() async {
        let clock = TestClock()
        let asked = LockIsolated<[Asked]>([])
        let more = [volumeHit, volumeFolderHit]
        var state = BrowseFixtures.state(Constants.myFilesFolder)
        state.searchScope = .everywhere
        state.searchQuery = Constants.query
        state.searchResults = [myHit]
        state.searchPhase = .loaded
        state.searchAnsweredTerm = Constants.query
        state.volumeSearch = BrowseFeature.VolumeSearch(
            phase: .loaded,
            results: [volumeHit],
            shortfall: .firstOnly(count: 1)
        )
        let store = BrowseFixtures.store(state) {
            $0.continuousClock = clock
            $0.filesClient.search = { _, path, _, limit in
                asked.withValue { $0.append(Asked(path: path, limit: limit)) }
                return SearchPage(items: more)
            }
        }

        await store.send(.searchVolumesShowMoreTapped) {
            $0.volumeSearch.limit = FilesClient.searchLimitSteps[1]
            $0.volumeSearch.phase = .loading
        }
        await store.receive(\.searchVolumesResponse) {
            $0.volumeSearch.phase = .loaded
            $0.volumeSearch.results = more
            $0.volumeSearch.shortfall = nil
        }

        #expect(asked.value == [Asked(path: "", limit: FilesClient.searchLimitSteps[1])])
    }

    @Test("An answer for an older term never lands in Volumes")
    func staleVolumesAnswerIsIgnored() async {
        var state = BrowseFixtures.state(Constants.myFilesFolder)
        state.searchScope = .everywhere
        state.searchQuery = Constants.query
        state.volumeSearch.phase = .loading
        let store = BrowseFixtures.store(state)

        await store.send(.searchVolumesResponse(.success([volumeHit]), term: "pla"))
    }

    @Test("Kind chips filter both sections and count both")
    func kindChipsFilterBothSections() {
        var state = BrowseFixtures.state(Constants.myFilesFolder)
        state.searchScope = .everywhere
        state.searchQuery = Constants.query
        state.searchResults = [myHit]
        state.volumeSearch.results = [volumeHit, volumeFolderHit]

        #expect(Set(state.availableSearchCategories) == [.document, .folder])
        #expect(state.searchCategoryCounts[.document] == 2)

        state.selectedSearchCategories = [.folder]

        #expect(state.displayedSearchResults?.isEmpty == true)
        #expect(state.displayedVolumeResults == [volumeFolderHit])
        #expect(!state.isEverySearchLaneEmpty)
    }
}
