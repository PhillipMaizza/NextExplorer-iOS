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
    private let photo = BrowseFixtures.file(TestFile.vacationPhoto, in: TestFolder.documents)

    // MARK: Share impact of a delete

    @Test("Asking to delete shows the confirmation and checks how many shares the delete would remove")
    func deleteTappedSetsTheDeleteConfirmationItemAndChecksShareImpact() async {
        let checked = LockIsolated<[[String]]>([])
        let store = BrowseFixtures.store(BrowseFixtures.state(
            TestFolder.documents,
            access: BrowseTestSupport.fullAccess
        )) {
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
        #expect(checked.value == [[TestFile.vacationPhoto]])
    }

    @Test("A failed share impact check is shown as unavailable and does not block the delete")
    func deleteTappedTreatsAFailedShareImpactCheckAsUnavailable() async {
        let store = BrowseFixtures.store(BrowseFixtures.state(
            TestFolder.documents,
            access: BrowseTestSupport.fullAccess
        )) {
            $0.filesClient.deleteImpact = { _, _ in throw FilesClientError.network(TestFailure.offline) }
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
        var state = BrowseFixtures.state(TestFolder.documents, items: [photo])
        state.favoritePaths = [photo.id]
        state.deleteConfirmationItem = photo
        let deleted = LockIsolated<[[String]]>([])
        let store = BrowseFixtures.store(state) {
            $0.filesClient.deleteItems = { _, items, _, _ in
                deleted.withValue { $0.append(items.map(\.id)) }
                return DeleteOutcome()
            }
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
        #expect(deleted.value == [[photo.id]])
    }

    @Test("Deleting an item that is not a favorite does not tell the Favorites tab to refresh")
    func deleteConfirmedOfANonFavoritedItemDoesNotSignalTheFavoritesTabToRefresh() async {
        var state = BrowseFixtures.state(TestFolder.documents, items: [photo])
        state.deleteConfirmationItem = photo
        let store = BrowseFixtures.store(state) {
            $0.filesClient.deleteItems = { _, _, _, _ in DeleteOutcome() }
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
        var state = BrowseFixtures.state(TestFolder.documents, items: [photo])
        state.deleteConfirmationItem = photo
        let store = BrowseFixtures.store(state) {
            $0.filesClient.deleteItems = { _, _, _, _ in throw FilesClientError.server(statusCode: 403) }
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
        var state = BrowseFixtures.state(TestFolder.documents, items: [photo])
        state.previewItem = photo
        state.deleteConfirmationItem = photo
        let clock = TestClock()
        let store = BrowseFixtures.store(state) {
            $0.continuousClock = clock
            $0.filesClient.deleteItems = { _, _, _, _ in DeleteOutcome() }
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
    func extractZipAddsTheExtractedFolderOnSuccess() async {
        let archive = BrowseFixtures.file(FilesFeatureTestValue.bundleName)
        let extracted = BrowseFixtures.folder("bundle")
        let store = BrowseFixtures.store(BrowseFixtures.state(items: [archive], access: BrowseTestSupport.fullAccess)) {
            $0.filesClient.extractZip = { _, _ in extracted }
        }

        await store.send(.extractTapped(archive)) {
            $0.isPerformingFileAction = true
            $0.fileActionProgressMessage = "Extracting…"
        }
        await store.receive(\.extractResponse.success) {
            $0.isPerformingFileAction = false
            $0.fileActionProgressMessage = nil
            $0.items = [archive, extracted]
            $0.selectedItemIDs = [extracted.id]
            $0.scrollTargetID = extracted.id
        }
    }

    @Test("Extract here puts every entry of the archive in the folder on screen")
    func extractHerePlacesEveryEntryInTheFolder() async {
        let archive = BrowseFixtures.file(FilesFeatureTestValue.bundleName)
        let notes = BrowseFixtures.file(TestFile.notes)
        let photo = BrowseFixtures.file(TestFile.aPhoto)
        let store = BrowseFixtures.store(BrowseFixtures.state(items: [archive], access: BrowseTestSupport.fullAccess)) {
            $0.filesClient.extractZipHere = { _, _ in [notes, photo] }
        }

        await store.send(.extractHereTapped(archive)) {
            $0.isPerformingFileAction = true
            $0.fileActionProgressMessage = "Extracting…"
        }
        await store.receive(\.extractResponse.success) {
            $0.isPerformingFileAction = false
            $0.fileActionProgressMessage = nil
            $0.items = [archive, notes, photo]
            $0.selectedItemIDs = [notes.id, photo.id]
            $0.scrollTargetID = notes.id
        }
    }

    @Test("Entries picked inside an archive come out beside it through the archive route")
    func pickedEntriesExtractBesideTheArchive() async {
        let archive = BrowseFixtures.file(FilesFeatureTestValue.bundleName)
        let extracted = BrowseFixtures.file(TestFile.notes)
        let asked = LockIsolated<[String]>([])
        let store = BrowseFixtures.store(BrowseFixtures.state(items: [archive], access: BrowseTestSupport.fullAccess)) {
            $0.filesClient.extractArchiveEntries = { _, _, paths in
                asked.setValue(paths)
                return [extracted]
            }
        }

        await store.send(.extractTapped(archive, entryPaths: [TestFile.notes])) {
            $0.isPerformingFileAction = true
            $0.fileActionProgressMessage = "Extracting…"
        }
        await store.receive(\.extractResponse.success) {
            $0.isPerformingFileAction = false
            $0.fileActionProgressMessage = nil
            $0.items = [archive, extracted]
            $0.selectedItemIDs = [extracted.id]
            $0.scrollTargetID = extracted.id
        }
        #expect(asked.value == [TestFile.notes])
    }

    @Test("A failed extraction shows a readable message")
    func extractFailureSurfacesAReadableErrorMessage() async {
        let store = BrowseFixtures.store(BrowseFixtures.state(access: BrowseTestSupport.fullAccess)) {
            $0.filesClient.extractZip = { _, _ in throw FilesClientError.server(statusCode: 415) }
        }

        await store.send(.extractTapped(BrowseFixtures.file(FilesFeatureTestValue.bundleName))) {
            $0.isPerformingFileAction = true
            $0.fileActionProgressMessage = "Extracting…"
        }
        await store.receive(\.extractResponse.failure) {
            $0.isPerformingFileAction = false
            $0.fileActionProgressMessage = nil
            $0.fileActionErrorMessage = FilesClientError.server(statusCode: 415).userMessage
        }
    }

    @Test("Compressing adds the new archive, then reloads the listing so it carries the server's metadata")
    func compressTappedAddsTheNewArchiveOnSuccess() async {
        let folder = BrowseFixtures.folder(TestFolder.photos, in: TestFolder.documents)
        let archive = BrowseFixtures.file("Photos.zip", in: TestFolder.documents)
        let favorites = AsyncGate()
        let state = BrowseFixtures.state(TestFolder.documents, items: [folder], access: BrowseTestSupport.fullAccess)
        let store = BrowseFixtures.store(state) {
            $0.filesClient.compressItems = { _, _ in archive }
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
            $0.selectedItemIDs = [archive.id]
            $0.scrollTargetID = archive.id
            $0.phase = .loading
        }
        await store.receive(\.itemsResponse.success) {
            $0.phase = .loaded
        }
        await store.receive(\.offlineAvailabilityComputed)
        favorites.open()
        await store.receive(\.favoritesResponse) {
            $0.hasLoadedFavorites = true
        }
        await store.finish()
    }

    @Test("Compressing a selection sends every selected item in one request, as the web does")
    func compressSelectionSendsEverySelectedItem() async {
        let picked = [
            BrowseFixtures.folder(TestFolder.photos, in: TestFolder.documents),
            BrowseFixtures.file(TestFile.notes, in: TestFolder.documents),
        ]
        let sent = LockIsolated<[String]>([])
        var state = BrowseFixtures.state(TestFolder.documents, items: picked, access: BrowseTestSupport.fullAccess)
        state.selectedItemIDs = Set(picked.map(\.id))
        let store = BrowseFixtures.store(state) {
            $0.filesClient.compressItems = { _, items in
                sent.setValue(items.map(\.id))
                throw FilesClientError.server(statusCode: 403)
            }
        }

        await store.send(.compressSelectionTapped) {
            $0.isPerformingFileAction = true
            $0.fileActionProgressMessage = "Compressing…"
        }
        await store.receive(\.compressResponse.failure) {
            $0.isPerformingFileAction = false
            $0.fileActionProgressMessage = nil
            $0.fileActionErrorMessage = FilesClientError.server(statusCode: 403).userMessage
        }
        #expect(Set(sent.value) == Set(picked.map(\.id)))
    }

    @Test("Compress and Extract do nothing where the server refuses new files or folders")
    func archiveActionsFollowTheCreateFlags() async {
        let archive = BrowseFixtures.file(FilesFeatureTestValue.bundleName)
        let filesOnly = FileAccess(
            canRead: true, canWrite: true, canUpload: true, canDelete: true, canShare: true, canDownload: true,
            canCreateFolder: false, canCreateFile: true
        )
        let readOnly = FileAccess(
            canRead: true, canWrite: true, canUpload: false, canDelete: true, canShare: true, canDownload: true,
            canCreateFolder: false, canCreateFile: false
        )
        #expect(filesOnly.canCompress && !filesOnly.canExtract)
        #expect(!readOnly.canCompress)

        await BrowseFixtures.store(BrowseFixtures.state(items: [archive], access: filesOnly))
            .send(.extractTapped(archive))
        await BrowseFixtures.store(BrowseFixtures.state(items: [archive], access: readOnly))
            .send(.compressTapped(archive))
    }

    @Test("A failed compression shows a readable message")
    func compressTappedFailureSurfacesAReadableErrorMessage() async {
        let store = BrowseFixtures.store(BrowseFixtures.state(
            TestFolder.documents,
            access: BrowseTestSupport.fullAccess
        )) {
            $0.filesClient.compressItems = { _, _ in throw FilesClientError.server(statusCode: 403) }
        }

        await store.send(.compressTapped(BrowseFixtures.folder(TestFolder.photos, in: TestFolder.documents))) {
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
