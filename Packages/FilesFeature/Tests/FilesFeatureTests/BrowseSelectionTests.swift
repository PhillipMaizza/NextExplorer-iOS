import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Testing
import TestUtils

@Suite(.isolatedDependencies)
@MainActor
struct BrowseSelectionTests {
    private let folder = BrowseFixtures.folder("A")
    private let file = BrowseFixtures.file("B.txt")

    private func selectingState(selected: Set<String> = []) -> BrowseFeature.State {
        var state = BrowseFixtures.state(items: [folder, file])
        state.isSelecting = true
        state.selectedItemIDs = selected
        return state
    }

    // MARK: Selecting

    @Test("Toggling select mode on starts selecting")
    func selectModeToggledEntersSelectMode() async {
        let store = BrowseFixtures.store()

        await store.send(.selectModeToggled) {
            $0.isSelecting = true
        }
    }

    @Test("Leaving select mode clears the selection")
    func selectModeToggledExitingClearsAnyExistingSelection() async {
        let store = BrowseFixtures.store(selectingState(selected: ["a", "b"]))

        await store.send(.selectModeToggled) {
            $0.isSelecting = false
            $0.selectedItemIDs = []
        }
    }

    @Test("Toggling an item adds it to the selection, and toggling it again removes it")
    func itemSelectionToggledAddsThenRemovesTheSameID() async {
        let store = BrowseFixtures.store(selectingState())

        await store.send(.itemSelectionToggled("a")) {
            $0.selectedItemIDs = ["a"]
        }
        await store.send(.itemSelectionToggled("a")) {
            $0.selectedItemIDs = []
        }
    }

    @Test("Select all selects every displayed item, and deselect all clears it")
    func selectAllTappedSelectsEveryDisplayedItem() async {
        let store = BrowseFixtures.store(selectingState())

        await store.send(.selectAllTapped) {
            $0.selectedItemIDs = [folder.id, file.id]
        }
        await store.send(.deselectAllTapped) {
            $0.selectedItemIDs = []
        }
    }

    // MARK: Bulk delete

    @Test("Bulk delete with nothing selected does not show the confirmation")
    func bulkDeleteTappedWithAnEmptySelectionDoesNotShowTheConfirmation() async {
        let store = BrowseFixtures.store(selectingState())

        await store.send(.bulkDeleteTapped)
    }

    @Test("Bulk delete shows the confirmation and checks the share impact of every selected item")
    func bulkDeleteTappedChecksShareImpactForEverySelectedItem() async {
        let checked = LockIsolated<[Set<String>]>([])
        let store = BrowseFixtures.store(selectingState(selected: [folder.id, file.id])) {
            $0.filesClient.deleteImpact = { _, items in
                checked.withValue { $0.append(Set(items.map(\.name))) }
                return DeleteImpact(shareCount: 3)
            }
        }

        await store.send(.bulkDeleteTapped) {
            $0.bulkDeleteConfirmationIsPresented = true
            $0.deleteImpactCheck = .checking
        }
        await store.receive(\.deleteImpactResponse.success) {
            $0.deleteImpactCheck = .loaded(DeleteImpact(shareCount: 3))
        }
        #expect(checked.value == [["A", "B.txt"]])
    }

    @Test("Confirming a bulk delete deletes every selected item in one call and leaves select mode")
    func bulkDeleteConfirmedDeletesEverySelectedItemInOneCall() async {
        var state = selectingState(selected: [folder.id, file.id])
        state.bulkDeleteConfirmationIsPresented = true
        state.favoritePaths = [folder.id]
        let deleted = LockIsolated<[Set<String>]>([])
        let store = BrowseFixtures.store(state) {
            $0.filesClient.deleteItems = { _, items in deleted.withValue { $0.append(Set(items.map(\.id))) } }
        }

        await store.send(.bulkDeleteConfirmed) {
            $0.bulkDeleteConfirmationIsPresented = false
            $0.isBulkActionInFlight = true
        }
        await store.receive(\.bulkDeleteResponse.success) {
            $0.isBulkActionInFlight = false
            $0.items = []
            $0.favoritePaths = []
            $0.isSelecting = false
            $0.selectedItemIDs = []
        }
        await store.receive(.delegate(.favoritesChanged))
        #expect(deleted.value == [["A", "B.txt"]])
    }

    @Test("A failed bulk delete shows a readable message and keeps the selection")
    func bulkDeleteConfirmedFailureSurfacesAReadableErrorMessage() async {
        let store = BrowseFixtures.store(selectingState(selected: [folder.id])) {
            $0.filesClient.deleteItems = { _, _ in throw FilesClientError.server(statusCode: 403) }
        }

        await store.send(.bulkDeleteConfirmed) {
            $0.bulkDeleteConfirmationIsPresented = false
            $0.isBulkActionInFlight = true
        }
        await store.receive(\.bulkDeleteResponse.failure) {
            $0.isBulkActionInFlight = false
            $0.fileActionErrorMessage = FilesClientError.server(statusCode: 403).userMessage
        }
    }

    // MARK: Downloads

    @Test("Bulk download with nothing selected does nothing")
    func bulkDownloadWithNothingSelectedDoesNothing() async {
        let store = BrowseFixtures.store(selectingState())

        await store.send(.bulkDownloadTapped)
    }

    // iOS hands downloads to the app queue; macOS saves via a panel, see MacDownloadTests.
    #if os(iOS)
        @Test("Downloading hands the item to the app download queue")
        func downloadTappedHandsTheItemToTheAppDownloadQueue() async {
            let item = BrowseFixtures.file("movie.mkv", in: TestFolder.files, size: 1_600_000_000)
            let store = BrowseFixtures.store(BrowseFixtures.state(TestFolder.files, title: TestFolder.files))

            await store.send(.downloadTapped(item))
            await store.receive(.delegate(.downloadRequested([item])))
        }

        @Test("Downloading from a preview also confirms with a toast")
        func downloadTappedFromAPreviewAlsoConfirmsWithAToast() async {
            let item = BrowseFixtures.file("movie.mkv", in: TestFolder.files)
            var state = BrowseFixtures.state(TestFolder.files, title: TestFolder.files)
            state.previewItem = item
            let store = BrowseFixtures.store(state)

            await store.send(.downloadTapped(item)) {
                $0.downloadSuccessMessage = "Downloading movie.mkv"
            }
            await store.receive(.delegate(.downloadRequested([item])))
        }

        @Test("Bulk download queues the selection in listing order and leaves select mode")
        func bulkDownloadTappedQueuesTheSelectionInListingOrderAndLeavesSelectMode() async {
            let photos = BrowseFixtures.folder(TestFolder.photos, in: TestFolder.files)
            let notes = BrowseFixtures.file(TestFile.notes, in: TestFolder.files, size: 1)
            let skipped = BrowseFixtures.file("skip.txt", in: TestFolder.files, size: 1)
            var state = BrowseFixtures.state(TestFolder.files, title: TestFolder.files, items: [photos, notes, skipped])
            state.isSelecting = true
            state.selectedItemIDs = [notes.id, photos.id]
            let store = BrowseFixtures.store(state)

            await store.send(.bulkDownloadTapped) {
                $0.isSelecting = false
                $0.selectedItemIDs = []
            }
            await store.receive(.delegate(.downloadRequested([photos, notes])))
        }
    #endif
}
