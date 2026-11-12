import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Testing
import TestUtils

@Suite(.isolatedDependencies)
@MainActor
struct BrowseDeleteAndArchiveTests {
    private let photo = BrowseFixtures.file("vacation.jpg")

    // MARK: Share impact of a delete

    @Test("Asking to delete shows the confirmation and checks how many shares the delete would remove")
    func deleteTappedSetsTheDeleteConfirmationItemAndChecksShareImpact() async {
        let checked = LockIsolated<[[String]]>([])
        let store = BrowseFixtures.store {
            $0.filesClient.deleteImpact = { _, items in
                checked.withValue { $0.append(items.map(\.name)) }
                return DeleteImpact(shareCount: 2)
            }
        }

        await store.send(.deleteTapped(photo)) {
            $0.deleteConfirmationItem = photo
            $0.deleteImpactCheck = .checking
        }
        await store.receive(\.deleteImpactResponse.success) {
            $0.deleteImpactCheck = .loaded(DeleteImpact(shareCount: 2))
        }
        #expect(checked.value == [["vacation.jpg"]])
    }

    @Test("A failed share impact check is shown as unavailable and does not block the delete")
    func deleteTappedTreatsAFailedShareImpactCheckAsUnavailable() async {
        let store = BrowseFixtures.store {
            $0.filesClient.deleteImpact = { _, _ in throw FilesClientError.network("offline") }
        }

        await store.send(.deleteTapped(photo)) {
            $0.deleteConfirmationItem = photo
            $0.deleteImpactCheck = .checking
        }
        await store.receive(\.deleteImpactResponse.failure) {
            $0.deleteImpactCheck = .unavailable
        }
    }

    @Test("Cancelling the confirmation clears the item and the share impact check")
    func deleteCancelledClearsTheDeleteConfirmationItemAndShareImpactCheck() async {
        var state = BrowseFixtures.state()
        state.deleteConfirmationItem = photo
        state.deleteImpactCheck = .loaded(DeleteImpact(shareCount: 1))
        let store = BrowseFixtures.store(state)

        await store.send(.deleteCancelled) {
            $0.deleteConfirmationItem = nil
            $0.deleteImpactCheck = .idle
        }
    }

    // MARK: Delete

    @Test("A confirmed delete removes the item and its favorite, and tells the Favorites tab")
    func deleteConfirmedRemovesTheItemAndItsFavoriteOnSuccess() async {
        var state = BrowseFixtures.state(items: [photo])
        state.favoritePaths = [photo.id]
        state.deleteConfirmationItem = photo
        let deleted = LockIsolated<[[String]]>([])
        let store = BrowseFixtures.store(state) {
            $0.filesClient.deleteItems = { _, items in deleted.withValue { $0.append(items.map(\.id)) } }
        }

        await store.send(.deleteConfirmed) {
            $0.deleteConfirmationItem = nil
            $0.isPerformingFileAction = true
        }
        await store.receive(\.deleteResponse.success) {
            $0.isPerformingFileAction = false
            $0.items = []
            $0.favoritePaths = []
        }
        await store.receive(.delegate(.favoritesChanged))
        #expect(deleted.value == [["vacation.jpg"]])
    }

    @Test("Deleting an item that is not a favorite does not tell the Favorites tab to refresh")
    func deleteConfirmedOfANonFavoritedItemDoesNotSignalTheFavoritesTabToRefresh() async {
        var state = BrowseFixtures.state(items: [photo])
        state.deleteConfirmationItem = photo
        let store = BrowseFixtures.store(state) {
            $0.filesClient.deleteItems = { _, _ in }
        }

        await store.send(.deleteConfirmed) {
            $0.deleteConfirmationItem = nil
            $0.isPerformingFileAction = true
        }
        await store.receive(\.deleteResponse.success) {
            $0.isPerformingFileAction = false
            $0.items = []
        }
    }

    @Test("A failed delete shows a readable message and keeps the item")
    func deleteConfirmedFailureSurfacesAReadableErrorMessageAndKeepsTheItem() async {
        var state = BrowseFixtures.state(items: [photo])
        state.deleteConfirmationItem = photo
        let store = BrowseFixtures.store(state) {
            $0.filesClient.deleteItems = { _, _ in throw FilesClientError.server(statusCode: 403) }
        }

        await store.send(.deleteConfirmed) {
            $0.deleteConfirmationItem = nil
            $0.isPerformingFileAction = true
        }
        await store.receive(\.deleteResponse.failure) {
            $0.isPerformingFileAction = false
            $0.fileActionErrorMessage = FilesClientError.server(statusCode: 403).userMessage
        }
    }

    @Test("Deleting from the preview closes the cover at once and deletes after the settle delay")
    func deleteConfirmedFromPreviewDismissesTheCoverThenDeletesAfterASettle() async {
        var state = BrowseFixtures.state(items: [photo])
        state.previewItem = photo
        state.deleteConfirmationItem = photo
        let clock = TestClock()
        let store = BrowseFixtures.store(state) {
            $0.continuousClock = clock
            $0.filesClient.deleteItems = { _, _ in }
        }

        await store.send(.deleteConfirmedFromPreview) {
            $0.deleteConfirmationItem = nil
            $0.isPerformingFileAction = true
        }
        // The cover closes right away; the request waits for the settle so the row animates out of
        // the list, not in the middle of the transition.
        await store.receive(.previewDismissed) {
            $0.previewItem = nil
        }
        await clock.advance(by: .milliseconds(350))
        await store.receive(\.deleteResponse.success) {
            $0.isPerformingFileAction = false
            $0.items = []
        }
    }

    // MARK: Extract and compress

    @Test("Extracting a zip adds the extracted folder beside it")
    func extractZipTappedAddsTheExtractedFolderOnSuccess() async {
        let archive = BrowseFixtures.file("bundle.zip")
        let extracted = BrowseFixtures.folder("bundle")
        let store = BrowseFixtures.store(BrowseFixtures.state(items: [archive])) {
            $0.filesClient.extractZip = { _, _ in extracted }
        }

        await store.send(.extractZipTapped(archive)) {
            $0.isPerformingFileAction = true
            $0.fileActionProgressMessage = "Extracting…"
        }
        await store.receive(\.extractZipResponse.success) {
            $0.isPerformingFileAction = false
            $0.fileActionProgressMessage = nil
            $0.items = [archive, extracted]
        }
    }

    @Test("A failed extraction shows a readable message")
    func extractZipTappedFailureSurfacesAReadableErrorMessage() async {
        let store = BrowseFixtures.store {
            $0.filesClient.extractZip = { _, _ in throw FilesClientError.server(statusCode: 415) }
        }

        await store.send(.extractZipTapped(BrowseFixtures.file("bundle.zip"))) {
            $0.isPerformingFileAction = true
            $0.fileActionProgressMessage = "Extracting…"
        }
        await store.receive(\.extractZipResponse.failure) {
            $0.isPerformingFileAction = false
            $0.fileActionProgressMessage = nil
            $0.fileActionErrorMessage = FilesClientError.server(statusCode: 415).userMessage
        }
    }

    @Test("Compressing adds the new archive, then reloads the listing so it carries the server's metadata")
    func compressTappedAddsTheNewArchiveOnSuccess() async {
        let folder = BrowseFixtures.folder("Documents")
        let archive = BrowseFixtures.file("Documents.zip")
        let favorites = AsyncGate()
        let store = BrowseFixtures.store(BrowseFixtures.state(items: [folder])) {
            $0.filesClient.compressItem = { _, _ in archive }
            $0.serveEmptyFolders()
            $0.serveListing([folder, archive], access: BrowseTestSupport.fullAccess)
            $0.holdFavorites(favorites)
        }

        await store.send(.compressTapped(folder)) {
            $0.isPerformingFileAction = true
            $0.fileActionProgressMessage = "Compressing…"
        }
        await store.receive(\.compressResponse.success) {
            $0.isPerformingFileAction = false
            $0.fileActionProgressMessage = nil
            $0.items = [folder, archive]
            $0.phase = .loading
        }
        await store.receive(\.itemsResponse.success) {
            $0.phase = .loaded
            $0.access = BrowseTestSupport.fullAccess
        }
        await store.receive(\.offlineAvailabilityComputed)
        favorites.open()
        await store.receive(\.favoritesResponse) {
            $0.hasLoadedFavorites = true
        }
        await store.finish()
    }

    @Test("A failed compression shows a readable message")
    func compressTappedFailureSurfacesAReadableErrorMessage() async {
        let store = BrowseFixtures.store {
            $0.filesClient.compressItem = { _, _ in throw FilesClientError.server(statusCode: 403) }
        }

        await store.send(.compressTapped(BrowseFixtures.folder("Documents"))) {
            $0.isPerformingFileAction = true
            $0.fileActionProgressMessage = "Compressing…"
        }
        await store.receive(\.compressResponse.failure) {
            $0.isPerformingFileAction = false
            $0.fileActionProgressMessage = nil
            $0.fileActionErrorMessage = FilesClientError.server(statusCode: 403).userMessage
        }
    }
}
