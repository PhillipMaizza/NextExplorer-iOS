#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import FilesClient
    @testable import FilesFeature
    import FolderPickerFeature
    import Foundation
    import Localization
    import Testing
    import TestUtils

    @MainActor
    @Suite(.isolatedDependencies)
    struct InspectorSelectionTests {
        private let report = BrowseFixtures.file(TestFile.report, in: TestFolder.docs)
        private let notes = BrowseFixtures.file(TestFile.notes, in: TestFolder.docs)

        private nonisolated func metadata(of item: FileItem) -> FileMetadata {
            FileMetadata(
                path: item.id,
                name: item.name,
                kind: item.kind,
                size: item.size,
                dateModified: MockDate.date,
                dateCreated: MockDate.date
            )
        }

        private func showingSelection(in path: String = TestFolder.docs) -> BrowseFeature.State {
            var state = BrowseFixtures.state(path, title: TestFolder.docs, items: [report, notes])
            state.selectedItemIDs = [report.id, notes.id]
            state.isInfoShowingSelection = true
            return state
        }

        @Test("Get Info on several selected items shows the selection, and again closes it")
        func getInfoOnSeveralItemsShowsTheSelection() async {
            var state = BrowseFixtures.state(TestFolder.docs, title: TestFolder.docs, items: [report, notes])
            state.selectedItemIDs = [report.id, notes.id]
            let store = BrowseFixtures.store(state)

            await store.send(.infoSelectionTapped) {
                $0.isInfoShowingSelection = true
            }
            await store.send(.infoSelectionTapped)
            await store.receive(\.infoDismissed) {
                $0.isInfoShowingSelection = false
            }
        }

        @Test("Get Info at the root opens nothing, with or without a selection")
        func getInfoAtTheRootOpensNothing() async {
            var state = BrowseFixtures.state(items: [report, notes])
            let store = BrowseFixtures.store(state)
            await store.send(.infoSelectionTapped)

            state.selectedItemIDs = [report.id]
            let selected = BrowseFixtures.store(state)
            await selected.send(.infoSelectionTapped)
        }

        @Test("An open inspector switches to the selection and drops the item load in flight")
        func anOpenInspectorSwitchesToTheSelection() async {
            let metadataGate = AsyncGate()
            let reportMetadata = metadata(of: report)
            let state = BrowseFixtures.state(TestFolder.docs, title: TestFolder.docs, items: [report, notes])
            let store = BrowseFixtures.store(state) {
                $0.filesClient.fetchMetadata = { _, _ in
                    try await metadataGate.wait()
                    return reportMetadata
                }
            }

            await store.send(.infoTapped(report)) {
                $0.infoItem = report
                $0.infoPhase = .loading
            }
            await store.send(.tableSelectionChanged([report.id, notes.id])) {
                $0.selectedItemIDs = [report.id, notes.id]
                $0.infoItem = nil
                $0.infoPhase = .idle
                $0.isInfoShowingSelection = true
            }
            metadataGate.open()
        }

        @Test("Narrowing the selection to one row shows that row after the settle delay")
        func narrowingTheSelectionShowsTheRow() async {
            let clock = TestClock()
            let notesMetadata = metadata(of: notes)
            let store = BrowseFixtures.store(showingSelection()) {
                $0.continuousClock = clock
                $0.filesClient.fetchMetadata = { _, _ in notesMetadata }
            }

            await store.send(.tableSelectionChanged([notes.id])) {
                $0.selectedItemIDs = [notes.id]
                $0.isInfoShowingSelection = false
                $0.infoItem = notes
                $0.infoPhase = .loading
            }
            await clock.advance(by: BrowseFeature.Constants.inspectorFollowDelay)
            await store.receive(\.infoMetadataResponse.success) {
                $0.infoPhase = .loaded
                $0.infoMetadata = notesMetadata
            }
        }

        @Test("Clearing the selection shows the current folder")
        func clearingTheSelectionShowsTheFolder() async throws {
            let store = BrowseFixtures.store(showingSelection()) {
                $0.filesClient.fetchMetadata = { _, _ in throw FilesClientError.offline }
                $0.filesClient.fetchUsage = { _, _ in throw FilesClientError.offline }
            }
            let folder = try #require(store.state.folderItem(now: MockDate.date))

            await store.send(.tableSelectionChanged([])) {
                $0.selectedItemIDs = []
                $0.isInfoShowingSelection = false
                $0.infoItem = folder
                $0.infoPhase = .loading
            }
            await store.receive(\.infoMetadataResponse.failure) {
                $0.infoPhase = .failed(L10n.Error.offline)
            }
            await store.receive(\.infoUsageResponse.failure)
        }

        @Test("Clearing the selection at the root closes the inspector")
        func clearingTheSelectionAtTheRootCloses() async {
            let store = BrowseFixtures.store(showingSelection(in: ""))

            await store.send(.tableSelectionChanged([])) {
                $0.selectedItemIDs = []
                $0.isInfoShowingSelection = false
            }
        }

        @Test("Favoriting the selected folders keeps the table selection and the selection inspector")
        func favoritingKeepsTheSelectionInspector() async {
            let invoices = BrowseFixtures.folder(TestFolder.archive, in: TestFolder.docs)
            let photos = BrowseFixtures.folder(TestFolder.photos, in: TestFolder.docs)
            var state = BrowseFixtures.state(TestFolder.docs, title: TestFolder.docs, items: [invoices, photos])
            state.hasLoadedFavorites = true
            state.selectedItemIDs = [invoices.id, photos.id]
            state.isInfoShowingSelection = true
            let store = BrowseFixtures.store(state) {
                $0.filesClient.addFavorite = { _, path in BrowseFixtures.favorite(path) }
            }

            await store.send(.bulkFavoriteTapped) {
                $0.isBulkActionInFlight = true
            }
            await store.receive(\.bulkFavoriteResponse) {
                $0.isBulkActionInFlight = false
                $0.favoritePaths = [invoices.id, photos.id]
            }
            await store.receive(.delegate(.favoritesChanged))
        }

        @Test("Copy To on the selection opens the copy picker for every selected item")
        func copyToOnTheSelectionOpensTheCopyPicker() async {
            let store = BrowseFixtures.store(showingSelection())

            await store.send(.copySelectionToTapped) {
                $0.destinationPicker = DestinationPickerFeature.State(
                    serverURL: BrowseTestSupport.serverURL,
                    items: [report, notes],
                    isCopy: true
                )
            }
            #expect(store.state.destinationPicker?.purpose == .copy)
        }

        @Test("Deleting all but one selected row shows the row left")
        func deletingDownToOneRowShowsIt() async {
            let reportMetadata = metadata(of: report)
            let store = BrowseFixtures.store(showingSelection()) {
                $0.filesClient.fetchMetadata = { _, _ in reportMetadata }
            }

            await store.send(.deleteResponse(.success(BrowseFeature.DeleteResult(removedIDs: [notes.id])))) {
                $0.items = [report]
                $0.isInfoShowingSelection = false
                $0.infoItem = report
                $0.infoPhase = .loading
            }
            await store.receive(\.infoMetadataResponse.success) {
                $0.infoPhase = .loaded
                $0.infoMetadata = reportMetadata
            }
        }
    }
#endif
