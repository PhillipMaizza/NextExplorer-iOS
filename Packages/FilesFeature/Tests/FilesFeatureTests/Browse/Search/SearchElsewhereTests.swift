#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import FilesClient
    @testable import FilesFeature
    import Foundation
    import Testing
    import TestUtils

    @Suite(.isolatedDependencies)
    @MainActor
    struct SearchElsewhereTests {
        private let elsewhereHit = SearchResultItem(
            name: TestFile.vacationPhoto,
            path: TestFolder.documents,
            kind: SearchResultItem.fileKind,
            isNameMatch: true
        )
        private let insideHit = SearchResultItem(
            name: TestFile.vacationPhoto,
            path: TestPath.photos2026,
            kind: SearchResultItem.fileKind,
            isNameMatch: true
        )

        private func store(
            clock: TestClock<Duration>,
            elsewhere: @escaping @Sendable () async throws -> SearchPage
        ) -> TestStoreOf<BrowseFeature> {
            let state = BrowseFixtures.state(TestFolder.photos, title: TestFolder.photos)
            return BrowseFixtures.store(state) {
                $0.continuousClock = clock
                $0.filesClient.search = { _, path, _, _ in
                    path.isEmpty ? try await elsewhere() : []
                }
            }
        }

        private func searchFolder(_ store: TestStoreOf<BrowseFeature>, clock: TestClock<Duration>) async {
            await store.send(.searchQueryChanged(TestSearch.term)) {
                $0.searchQuery = TestSearch.term
                $0.searchResults = []
                $0.searchPhase = .loading
            }
            await clock.advance(by: FilesClient.searchDebounce)
            await store.receive(\.searchResultsResponse) {
                $0.searchAnsweredTerm = TestSearch.term
                $0.searchPhase = .loaded
                $0.elsewherePhase = .loading
            }
        }

        @Test("A folder search that finds nothing looks everywhere and lists what is outside the folder")
        func anEmptyFolderSearchLooksEverywhere() async {
            let clock = TestClock()
            let hits: SearchPage = [elsewhereHit, insideHit]
            let store = store(clock: clock) { hits }

            await searchFolder(store, clock: clock)
            await store.receive(\.searchElsewhereResponse) {
                $0.elsewhereResults = [elsewhereHit]
                $0.elsewherePhase = .loaded
            }
            #expect(store.state.isShowingElsewhereResults)
        }

        @Test("A failed look everywhere leaves the folder's no matches with its own button")
        func aFailedLookEverywhereIsSaid() async {
            let clock = TestClock()
            let store = store(clock: clock) { throw FilesClientError.offline }

            await searchFolder(store, clock: clock)
            await store.receive(\.searchElsewhereResponse) {
                $0.elsewherePhase = .failed(FilesClientError.offline.userMessage)
            }
            #expect(!store.state.isShowingElsewhereResults)
        }

        @Test("A newer term drops the look everywhere still in flight")
        func aNewerTermDropsTheLookEverywhere() async {
            let clock = TestClock()
            let gate = AsyncGate()
            let store = store(clock: clock) {
                try await gate.wait()
                return []
            }

            await searchFolder(store, clock: clock)
            await store.send(.searchQueryChanged(TestSearch.longerTerm)) {
                $0.searchQuery = TestSearch.longerTerm
                $0.searchPhase = .loading
                $0.searchAnsweredTerm = nil
                $0.elsewherePhase = .idle
            }
            gate.open()
            await clock.advance(by: FilesClient.searchDebounce)
            await store.receive(\.searchResultsResponse) {
                $0.searchAnsweredTerm = TestSearch.longerTerm
                $0.searchPhase = .loaded
                $0.elsewherePhase = .loading
            }
            await store.receive(\.searchElsewhereResponse) {
                $0.elsewherePhase = .loaded
            }
        }

        @Test("Show all results everywhere moves the whole search to Everywhere")
        func showAllMovesTheSearchEverywhere() async {
            let clock = TestClock()
            let hits: SearchPage = [elsewhereHit]
            let store = store(clock: clock) { hits }

            await searchFolder(store, clock: clock)
            await store.receive(\.searchElsewhereResponse) {
                $0.elsewhereResults = [elsewhereHit]
                $0.elsewherePhase = .loaded
            }
            await store.send(.searchScopeChanged(.everywhere)) {
                $0.searchScope = .everywhere
                $0.searchPhase = .loading
                $0.searchAnsweredTerm = nil
                $0.elsewhereResults = []
                $0.elsewherePhase = .idle
            }
            await store.receive(\.searchResultsResponse) {
                $0.searchPhase = .loaded
                $0.searchResults = [elsewhereHit]
                $0.searchAnsweredTerm = TestSearch.term
            }
        }
    }
#endif
